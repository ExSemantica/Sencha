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

  defstruct [:fsm_process, :has_hostname?, :nick_hash, :message_queue]

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

  @doc """
  Set nickname hash.
  """
  def send_nickname_hash(pid, hash) do
    GenServer.call(pid, {:send_nickname_hash, hash})
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

        {:continue,
         %__MODULE__{
           nick_hash: nil,
           has_hostname?: false,
           message_queue: :queue.new()
         }}

      {id, reason} ->
        socket |> nongraceful_disconnect("Banned (##{id}) (#{reason})")

        {:close,
         %__MODULE__{
           nick_hash: nil,
           has_hostname?: false,
           message_queue: :queue.new()
         }}
    end
  end

  @impl ThousandIsland.Handler
  def handle_data(data, socket, state = %__MODULE__{message_queue: queue, fsm_process: fsm}) do
    split = data |> String.split("\r\n", trim: true)
    qsize = :queue.len(queue)

    if qsize + length(split) > 10 do
      socket |> nongraceful_disconnect("Excess flood")
      {:close, state}
    else
      queue = split |> Enum.reduce(queue, fn s, q -> q |> :queue.snoc(s) end)

      if not is_nil(fsm) and Process.alive?(fsm) do
        send(self(), :flush)
      end

      {:continue, %__MODULE__{state | message_queue: queue}}
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
  def handle_info(
        :flush,
        {socket, state = %__MODULE__{message_queue: message_queue, fsm_process: fsm}}
      ) do
    if :queue.is_empty(message_queue) do
      {:noreply, {socket, %{state | message_queue: message_queue}}}
    else
      message = message_queue |> :queue.head()
      {:ok, decoded} = Sencha.Message.decode(message)
      Sencha.User.handle_message(fsm, decoded)

      send(self(), :flush)

      {:noreply, {socket, %{state | message_queue: message_queue |> :queue.drop()}}}
    end
  end

  @impl GenServer
  def handle_info({:EXIT, _pid, :normal}, {socket, state}) do
    {:noreply, {socket, state}}
  end

  @impl GenServer
  def handle_info(
        {:EXIT, pid, _reason},
        {socket, state = %__MODULE__{fsm_process: fsm, nick_hash: hash}}
      )
      when pid == fsm do
    :global.unregister_name({Sencha.User, hash})
    {:noreply, {socket, state}}
  end

  @impl GenServer
  def handle_info(
        {rdns_ref, {:lookup, peer_ip, host}},
        {socket, state = %__MODULE__{has_hostname?: false}}
      ) do
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

        Process.send_after(self(), :flush, 1000)

        {:noreply, {socket, %__MODULE__{state | fsm_process: fsm_process, has_hostname?: true}}}

      {:error, :max_children} ->
        disconnect(self(), "Server is over capacity, please reconnect later")

        {:noreply, {socket, state}}
    end
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

  @impl GenServer
  def handle_call({:send_nickname_hash, hash}, {pid, _tag}, {socket, state}) do
    {:reply,
     case :global.whereis_name({Sencha.User, hash}) do
       :undefined -> :global.register_name({Sencha.User, hash}, pid)
       ^pid -> :global.re_register_name({Sencha.User, hash}, pid)
       _other -> :already_in_use
     end, {socket, state}}
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
