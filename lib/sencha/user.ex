# ThousandIsland TCP user socket handler
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
defmodule Sencha.User do
  @moduledoc """
  ThousandIsland TCP user socket handler
  """
  require Logger
  use ThousandIsland.Handler

  defstruct [
    :has_hostname?,
    :nick?,
    :user?,
    :message_queue,
    :queue_flood_count,
    :target,
    :timeout_auth,
    :timeout_ping_soft,
    :timeout_ping_hard,
    :last_token,
    :gecos,
    :capabilities
  ]

  @max_connections 250
  @auth_milliseconds 15_000
  @ping_soft_milliseconds 105_000
  @ping_hard_milliseconds 120_000
  @flood_amount 5
  @flood_milliseconds 1_000

  @doc """
  All user mode characters that can be set by an non-operator
  """
  def modes(), do: MapSet.new(~c(wi))

  @doc """
  All user mode characters supported

  Not all can be set by a non-operator
  """
  def modes_all(), do: MapSet.new(~c(o)) |> MapSet.union(modes())

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
    Logger.debug(message)
    GenServer.cast(pid, {:message_send, message})
  end

  @doc """
  If this user is in the CIDR block, disconnect them

  Don't use a CIDR string here, use an `InetCidr` block
  The ID will be inserted into the ban reason
  """
  def check_kline(pid, cidr, id, reason) do
    GenServer.cast(pid, {:check_kline, cidr, id, reason})
  end

  @doc """
  Handle a pong command asynchronously
  """
  def handle_pong(pid, token) do
    GenServer.cast(pid, {:handle_pong, token})
  end

  @doc """
  Gets all user connection PIDs
  """
  def gather() do
    ThousandIsland.connection_pids(Sencha.Supervisor.User)
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

        # NOTE: ThousandIsland disconnects clients within a minute by default
        # Set a persistent, infinite timeout because `Sencha.User` handles
        # this all for us.
        {:continue,
         %__MODULE__{
           timeout_auth: Process.send_after(self(), :timeout_auth, @auth_milliseconds),
           has_hostname?: false,
           message_queue: :queue.new(),
           queue_flood_count: 0,
           nick?: false,
           user?: false,
           capabilities: :wait_for_caps
         }, {:persistent, :infinity}}

      {id, reason} ->
        socket |> nongraceful_disconnect("Banned (##{id}) (#{reason})", nil)

        {:close,
         %__MODULE__{
           has_hostname?: false,
           message_queue: :queue.new(),
           queue_flood_count: 0
         }}
    end
  end

  @impl ThousandIsland.Handler
  def handle_data(
        data,
        _socket,
        state = %__MODULE__{
          message_queue: queue,
          queue_flood_count: flood,
          has_hostname?: has_hostname?
        }
      ) do
    split = data |> String.replace("\r", "") |> String.split("\n", trim: true)

    queue = split |> Enum.reduce(queue, fn s, q -> q |> :queue.snoc(s) end)

    if has_hostname? do
      send(self(), :flush)
    end

    {:continue,
     %__MODULE__{state | message_queue: queue, queue_flood_count: flood + length(split)}}
  end

  @impl ThousandIsland.Handler
  def handle_shutdown(socket, %__MODULE__{target: target}) do
    socket |> nongraceful_disconnect("Server is shutting down", target[:nickname])

    :ok
  end

  @impl ThousandIsland.Handler
  def handle_error(_reason, socket, %__MODULE__{target: target}) do
    socket |> nongraceful_disconnect("Server error", target[:nickname])

    :ok
  end

  # ===========================================================================
  # GenServer callbacks
  # ===========================================================================
  @impl GenServer
  def handle_info(:timeout_auth, {socket, state}) do
    disconnect(self(), "Authentication timeout")

    {:noreply, {socket, state}}
  end

  @impl GenServer
  def handle_info(:ping_soft, {socket, state = %__MODULE__{last_token: last_token}}) do
    message_send(
      self(),
      %Sencha.Message{
        prefix: Application.fetch_env!(:sencha, :hostname),
        command: "PING",
        middle: ["Sencha-#{last_token}"]
      }
    )

    {:noreply, {socket, state}}
  end

  @impl GenServer
  def handle_info(:ping_hard, {socket, state = %__MODULE__{last_token: last_token}}) do
    this_token = DateTime.utc_now() |> DateTime.to_unix()
    this_token = this_token - last_token
    disconnect(self(), "Ping timeout (#{this_token} seconds)")

    {:noreply, {socket, state}}
  end

  @impl GenServer
  def handle_info(
        :flush,
        {socket, state = %__MODULE__{message_queue: message_queue}}
      ) do
    if :queue.is_empty(message_queue) do
      {:noreply, {socket, %{state | message_queue: message_queue}}}
    else
      message = message_queue |> :queue.head()
      {:ok, decoded} = Sencha.Message.decode(message)
      state = state |> message_recv(decoded)

      send(self(), :flush)

      {:noreply, {socket, %__MODULE__{state | message_queue: message_queue |> :queue.drop()}}}
    end
  end

  @impl GenServer
  def handle_info(:flood_check, {socket, state = %__MODULE__{queue_flood_count: flood}})
      when flood > @flood_amount do
    disconnect(self(), "Excess flood")
    {:noreply, {socket, state}}
  end

  @impl GenServer
  def handle_info(:flood_check, {socket, state = %__MODULE__{}}) do
    Process.send_after(self(), :flood_check, @flood_milliseconds)

    {:noreply, {socket, %__MODULE__{state | queue_flood_count: 0}}}
  end

  @impl GenServer
  def handle_info({:EXIT, _pid, :normal}, {socket, state}) do
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

    {:ok, connections} = gather()

    cond do
      length(connections) > @max_connections ->
        disconnect(self(), "Server is over capacity, please reconnect later")

        {:noreply, {socket, state}}

      true ->
        Process.send_after(self(), :flush, 1_000)
        Process.send_after(self(), :flood_check, @flood_milliseconds)

        {:noreply,
         {socket,
          %__MODULE__{
            state
            | has_hostname?: true,
              target: %{nickname: nil, user: nil, host: host}
          }}}
    end
  end

  @impl GenServer
  def handle_cast({:disconnect, reason}, {socket, state = %__MODULE__{target: target}}) do
    socket |> nongraceful_disconnect(reason, target[:nickname])

    {:noreply, {socket, state}}
  end

  @impl GenServer
  def handle_cast(
        {:handle_pong, token},
        {socket,
         state = %__MODULE__{
           last_token: last_token,
           timeout_ping_soft: soft,
           timeout_ping_hard: hard
         }}
      ) do
    if token == "Sencha-#{last_token}" do
      Process.cancel_timer(soft)
      Process.cancel_timer(hard)

      {:noreply,
       {socket,
        %__MODULE__{
          state
          | last_token: DateTime.utc_now() |> DateTime.to_unix(),
            timeout_ping_soft: Process.send_after(self(), :ping_soft, @ping_soft_milliseconds),
            timeout_ping_hard: Process.send_after(self(), :ping_hard, @ping_hard_milliseconds)
        }}}
    else
      {:noreply, {socket, state}}
    end
  end

  @impl GenServer
  def handle_cast(
        {:check_kline, cidr, id, reason},
        {socket, state}
      ) do
    {:ok, {peer_ip, _peer_port}} = socket |> ThousandIsland.Socket.peername()

    if InetCidr.contains?(cidr, peer_ip) do
      state |> Sencha.Dispatch.Numeric.send(:ERR_YOUREBANNEDCREEP)
      disconnect(self(), "Banned (##{id}) (#{reason})")
    end

    {:noreply, {socket, state}}
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
  defp nongraceful_disconnect(socket, reason, nickname) do
    # Unregister this now-unused nick no matter what
    if not is_nil(nickname) do
      :global.unregister_name({Sencha.User, String.downcase(nickname)})
    end

    host = Application.fetch_env!(:sencha, :hostname)

    {:ok, data} =
      %Sencha.Message{
        prefix: host,
        command: "ERROR",
        trailing: "Closing Link: [#{host}] (#{reason})"
      }
      |> Sencha.Message.encode()

    socket |> ThousandIsland.Socket.send(data <> "\r\n")
    socket |> ThousandIsland.Socket.shutdown(:read_write)
  end

  defp message_recv(
         state = %__MODULE__{timeout_auth: timeout_auth},
         message
       ) do
    Logger.debug(message)
    state = %__MODULE__{nick?: nick?, user?: user?, capabilities: caps_state} = state |> Sencha.Dispatch.handle(message)

    caps? =
      case caps_state do
        :wait_for_caps ->
          false

        {:stall_for_caps, _which} ->
          false

        :ignore ->
          true

        {:ok, _caps} ->
          true
      end

    cond do
      !!Process.read_timer(timeout_auth) and nick? and user? and caps? ->
        Process.cancel_timer(timeout_auth)

        # send the welcome burst
        state |> Sencha.Dispatch.Welcome.send_burst()

        # send soft and hard pings
        # soft one will ping and hard one will disconnect
        %__MODULE__{
          state
          | last_token: DateTime.utc_now() |> DateTime.to_unix(),
            timeout_ping_soft: Process.send_after(self(), :ping_soft, @ping_soft_milliseconds),
            timeout_ping_hard: Process.send_after(self(), :ping_hard, @ping_hard_milliseconds)
        }

      true ->
        state
    end
  end
end
