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
  use ThousandIsland.Handler

  defstruct [:fsm_process, :authenticated?]

  # ===========================================================================
  # Public API
  # ===========================================================================
  @spec disconnect(atom() | pid() | {atom(), any()} | {:via, atom(), any()}, any()) :: :ok
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
  # TCP and GenServer callbacks
  # ===========================================================================
  @impl ThousandIsland.Handler
  def handle_connection(socket, _state) do
    {:ok, {peer_ip, _peer_port}} = socket |> ThousandIsland.Socket.peername()
    {:ok, reason} = peer_ip |> Sencha.KLine.klined?()

    case reason do
      nil ->
        message_send(
          self(),
          %Sencha.Message{
            prefix: Application.fetch_env!(:sencha, :hostname),
            command: "NOTICE",
            middle: ["AUTH"],
            trailing: "Checking your hostname..."
          }
        )

        Task.async(fn ->
          __MODULE__.ReverseDNS.lookup(peer_ip)
        end)

        {:continue, []}

      reason ->
        disconnect(self(), "*** Banned (#{reason})")
        {:continue, []}
    end
  end

  @impl GenServer
  def handle_info({:EXIT, _reason, :normal}, {socket, state}) do
    {:noreply, {socket, state}}
  end

  @impl GenServer
  def handle_info({rdns_ref, {:lookup, peer_ip, host}}, {socket, []}) do
    Process.demonitor(rdns_ref, [:flush])

    host =
      case host do
        {:ok, host} ->
          message_send(
            self(),
            %Sencha.Message{
              prefix: Application.fetch_env!(:sencha, :hostname),
              command: "NOTICE",
              middle: ["AUTH"],
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
              middle: ["AUTH"],
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
        middle: ["AUTH"],
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

        {:noreply,
         {socket,
          %__MODULE__{
            fsm_process: fsm_process,
            authenticated?: false
          }}}

      {:error, :max_children} ->
        disconnect(
          self(),
          "Server is over capacity, please try again later"
        )

        {:stop, :normal, {socket, []}}
    end
  end

  @impl GenServer
  def handle_cast({:disconnect, reason}, {socket, state}) do
    host = Application.fetch_env!(:sencha, :hostname)

    # Don't use Erlang messages here because there will be a race condition
    data =
      %Sencha.Message{command: "ERROR", trailing: "Closing Link: [#{host}] (#{reason})"}
      |> Sencha.Message.encode()

    socket |> ThousandIsland.Socket.send(data <> "\r\n")

    {:stop, :normal, {socket, state}}
  end

  @impl GenServer
  def handle_cast({:message_send, message}, {socket, state}) do
    data =
      message
      |> Sencha.Message.encode()

    socket |> ThousandIsland.Socket.send(data <> "\r\n")
    {:noreply, {socket, state}}
  end
end
