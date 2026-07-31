# ThousandIsland TCP socket handler
# Copyright 2026 Roland Metivier
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
defmodule Sencha.Socket do
  @moduledoc """
  ThousandIsland TCP socket handler
  """
  require Logger
  use ThousandIsland.Handler

  defstruct [:fsm_process, :has_hostname?, :pending_data]

  # ===========================================================================
  # Public API
  # ===========================================================================
  @doc """
  Disconnect this PID from the IRC server
  """
  def disconnect(pid, reason) do
    GenServer.cast(pid, {:disconnect, reason})
  end

  @doc """
  Sends a `Sencha.Message`
  """
  def message_send(pid, message) do
    GenServer.cast(pid, {:message_send, message})
  end

  # ===========================================================================
  # TCP callbacks
  # ===========================================================================
  @impl ThousandIsland.Handler
  def handle_connection(socket, _state) do
    {:ok, {peer_ip, _peer_port}} = socket |> ThousandIsland.Socket.peername()
    {:ok, kline} = peer_ip |> Sencha.KLine.klined?()

    case kline do
      nil ->
        message_send(
          self(),
          %Sencha.Message{
            prefix: Application.fetch_env!(:sencha, :hostname),
            command: "NOTICE",
            middle: ["*"],
            trailing: "Checking your hostname..."
          }
        )

        Task.async(fn ->
          __MODULE__.ReverseDNS.lookup(peer_ip)
        end)

        {:continue, %__MODULE__{pending_data: "", has_hostname?: false}}

      {id, reason} ->
        socket |> nongraceful_disconnect("Banned (##{id}) (#{reason})")
        {:close, %__MODULE__{pending_data: "", has_hostname?: false}}
    end
  end

  @impl ThousandIsland.Handler
  def handle_data(data, _socket, state = %__MODULE__{pending_data: pending_data}) do
    case data |> String.split("\n", parts: 2, trim: true) do
      [d0, d1] ->
        d0 = d0 |> String.replace_suffix("\r", "")

        {:continue, %__MODULE__{state | pending_data: d1},
         {:continue, {:irc_data, pending_data <> d0}}}

      [d0] ->
        {:continue, %__MODULE__{state | pending_data: ""},
         {:continue, {:irc_data, pending_data <> d0}}}

      [] ->
        {:continue, state}
    end
  end

  @impl ThousandIsland.Handler
  def handle_shutdown(socket, _state) do
    socket |> nongraceful_disconnect("Server is shutting down")

    :ok
  end

  @impl ThousandIsland.Handler
  def handle_error(_reason, socket, _state) do
    socket |> nongraceful_disconnect("Server error")

    :ok
  end

  # ===========================================================================
  # GenServer callbacks
  # ===========================================================================
  @impl GenServer
  def handle_continue(
        {:irc_data, data},
        {socket, state = %__MODULE__{pending_data: pending_data}}
      ) do
    # TODO: How should we handle lengthy (>510 bytes) messages here?
    {:ok, decoded} = data |> Sencha.Message.decode()
    send(self(), {:message_recv, decoded})

    case pending_data |> String.split("\n", parts: 2, trim: true) do
      [d0, d1] ->
        d0 = d0 |> String.replace_suffix("\r", "")

        {:noreply, {socket, %__MODULE__{state | pending_data: d1}},
         {:continue, {:irc_data, pending_data <> d0}}}

      [d0] ->
        {:noreply, {socket, %__MODULE__{state | pending_data: pending_data <> d0}}}

      [] ->
        {:noreply, {socket, %__MODULE__{state | pending_data: ""}}}
    end
  end

  @impl GenServer
  def handle_info({:EXIT, _reason, :normal}, {socket, state}) do
    {:noreply, {socket, state}}
  end

  @impl GenServer
  def handle_info({rdns_ref, {:lookup, peer_ip, host}}, {socket, state = %__MODULE__{}}) do
    Process.demonitor(rdns_ref, [:flush])

    host =
      case host do
        {:ok, host} ->
          message_send(
            self(),
            %Sencha.Message{
              prefix: Application.fetch_env!(:sencha, :hostname),
              command: "NOTICE",
              middle: ["*"],
              trailing: "Found your hostname"
            }
          )

          host

        {:error, _error} ->
          message_send(
            self(),
            %Sencha.Message{
              prefix: Application.fetch_env!(:sencha, :hostname),
              command: "NOTICE",
              middle: ["*"],
              trailing: "Couldn't look up your hostname"
            }
          )

          peer_ip |> :inet.ntoa() |> to_string
      end

    message_send(
      self(),
      %Sencha.Message{
        prefix: Application.fetch_env!(:sencha, :hostname),
        command: "NOTICE",
        middle: ["*"],
        trailing: "Your hostname or IP address is " <> host
      }
    )

    case Sencha.Supervisor.User.start_user(
           socket: self(),
           ip_address: peer_ip,
           target: %{host: host}
         ) do
      {:ok, fsm_process} ->
        Process.link(fsm_process)

        {:noreply, {socket, %__MODULE__{state | fsm_process: fsm_process, has_hostname?: true}}}

      {:error, :max_children} ->
        disconnect(self(), "Server is over capacity, please reconnect later")

        {:noreply, {socket, state}}
    end
  end

  @impl GenServer
  def handle_info({:message_recv, message}, {socket, state}) do
    Logger.debug(message)

    {:noreply, {socket, state}}
  end

  @impl GenServer
  def handle_cast({:disconnect, reason}, {socket, state}) do
    socket |> nongraceful_disconnect(reason)

    {:stop, :normal, {socket, state}}
  end

  @impl GenServer
  def handle_cast({:message_send, message}, {socket, state}) do
    # TODO: How should we handle lengthy (>510 bytes) messages here?
    {:ok, data} =
      message
      |> Sencha.Message.encode()

    socket |> ThousandIsland.Socket.send(data <> "\r\n")

    {:noreply, {socket, state}}
  end

  # ===========================================================================
  # Private functions
  # ===========================================================================
  # A "dirty" disconnect that is useful in race condition prone spots
  defp nongraceful_disconnect(socket, reason) do
    host = Application.fetch_env!(:sencha, :hostname)

    {:ok, data} =
      %Sencha.Message{command: "ERROR", trailing: "Closing Link: [#{host}] (#{reason})"}
      |> Sencha.Message.encode()

    socket |> ThousandIsland.Socket.send(data <> "\r\n")
    socket |> ThousandIsland.Socket.shutdown(:read_write)
  end
end
