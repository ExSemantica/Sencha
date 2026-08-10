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
    :capabilities,
    :channel_hashes,
    :away_status
  ]

  @max_connections 250
  @auth_milliseconds 15_000
  @ping_soft_milliseconds 105_000
  @ping_hard_milliseconds 120_000
  @flood_amount 5
  @flood_milliseconds 1_000

  @doc """
  Interval in milliseconds to issue a ping
  """
  def ping_soft(), do: @ping_soft_milliseconds

  @doc """
  Interval in milliseconds to timeout for a missed ping
  """
  def ping_hard(), do: @ping_hard_milliseconds

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
  Sends a `Sencha.Message` when the socket is known
  """
  def message_send(socket, message) do
    # TODO: How should we handle lengthy (>510 bytes) messages here?
    {:ok, data} =
      message
      |> Sencha.Message.encode()

    Logger.debug(message)

    socket |> ThousandIsland.Socket.send(data <> "\r\n")

    socket
  end

  @doc """
  Sends a `Sencha.Message` if only the username is known
  """
  def remote_send(message, user_hash) do
    :global.send({__MODULE__, user_hash}, {:remote_send, message})
  end

  @doc """
  Disconnect this username from the IRC server
  """
  def remote_disconnect(user_hash, reason) do
    Logger.debug("Remote attempting to disconnect '#{user_hash}': #{reason}")
    :global.send({__MODULE__, user_hash}, {:disconnect, reason})
  end

  @doc """
  Disconnect yourself from the IRC server
  """
  def disconnect(
         socket,
         target,
         reason,
         channel_hashes
       ) do
    if not is_nil(target[:nickname]) do
      nick_hash = String.downcase(target.nickname)

      message =
        %Sencha.Message{
          prefix: target |> Sencha.Prefix.encode(),
          command: "QUIT",
          trailing: reason
        }

      neighbors =
        channel_hashes
        |> Enum.flat_map(&Sencha.Channel.gather_hashes/1)
        |> MapSet.new()
        |> MapSet.delete(nick_hash)
        |> MapSet.to_list()

      for neighbor <- neighbors do
        Sencha.User.remote_send(message, neighbor)
      end

      for channel_hash <- channel_hashes do
        :mnesia.transaction(fn ->
          case :mnesia.read(Sencha.Channel.Roster, channel_hash) do
            [{Sencha.Channel.Roster, ^channel_hash, others, attributes, modes}] ->
              :mnesia.write(
                {Sencha.Channel.Roster, channel_hash, others |> List.delete(target), attributes,
                 modes}
              )
          end
        end)

        Sencha.Channel.garbage_collect(channel_hash)
      end

      :global.unregister_name({Sencha.User, nick_hash})
    end

    {:ok, data} =
      %Sencha.Message{
        prefix: target.host,
        command: "ERROR",
        trailing: "Closing Link: [#{target.host}] (#{reason})"
      }
      |> Sencha.Message.encode()

    socket |> ThousandIsland.Socket.send(data <> "\r\n")
    socket |> ThousandIsland.Socket.shutdown(:read_write)

    :ok
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
  Gets all **local** user connection PIDs
  """
  def gather() do
    ThousandIsland.connection_pids(Sencha.Supervisor.User)
  end

  @doc """
  Send an away status to this user, **will use globals table**
  """
  def send_away_status(user_hash, respond_to_hash) do
    :global.send({__MODULE__, user_hash}, {:send_away_status, respond_to_hash})
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
        socket
        |> message_send(%Sencha.Message{
          prefix: Application.fetch_env!(:sencha, :hostname),
          command: "NOTICE",
          middle: ["*"],
          trailing: "Checking your hostname..."
        })

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
           capabilities: :wait_for_caps,
           channel_hashes: []
         }, {:persistent, :infinity}}

      {id, reason} ->
        socket
        |> disconnect(
          %{host: peer_ip |> :inet.ntoa() |> to_string},
          "Banned (##{id}) (#{reason})",
          []
        )

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
  def handle_shutdown(socket, %__MODULE__{target: target, channel_hashes: hashes}) do
    socket |> disconnect(target, "Server was shut down", hashes)

    :ok
  end

  @impl ThousandIsland.Handler
  def handle_close(socket, %__MODULE__{target: target, channel_hashes: hashes}) do
    socket |> disconnect(target, "Connection reset by peer", hashes)

    :ok
  end

  @impl ThousandIsland.Handler
  def handle_error(_reason, socket, %__MODULE__{target: target, channel_hashes: hashes}) do
    socket |> disconnect(target, "Server error", hashes)

    :ok
  end

  # ===========================================================================
  # GenServer callbacks
  # ===========================================================================
  @impl GenServer
  def handle_info(
        {:send_away_status, respond_to_hash},
        {socket, state = %__MODULE__{target: target, away_status: away_status}}
      ) do
    if not is_nil(away_status) do
      remote_send(
        Sencha.User.Numeric.encode(:ERR_CANNOTSENDTOCHAN, target, %{
          nick: target.nickname,
          status: away_status
        }),
        respond_to_hash
      )
    end

    {:noreply, {socket, state}}
  end

  @impl GenServer
  def handle_info(:timeout_auth, {socket, state = %__MODULE__{target: target}}) do
    socket |> disconnect(target, "Authentication timeout", [])

    {:noreply, {socket, state}}
  end

  @impl GenServer
  def handle_info(:ping_soft, {socket, state = %__MODULE__{last_token: last_token}}) do
    socket
    |> message_send(%Sencha.Message{
      prefix: Application.fetch_env!(:sencha, :hostname),
      command: "PING",
      middle: ["Sencha-#{last_token}"]
    })

    {:noreply, {socket, state}}
  end

  @impl GenServer
  def handle_info(
        :ping_hard,
        {socket,
         state = %__MODULE__{target: target, last_token: last_token, channel_hashes: hashes}}
      ) do
    this_token = DateTime.utc_now() |> DateTime.to_unix()
    this_token = this_token - last_token
    socket |> disconnect(target, "Ping timeout (#{this_token} seconds)", hashes)

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

      state =
        state
        |> message_recv(
          socket,
          decoded
        )

      send(self(), :flush)

      {:noreply, {socket, %__MODULE__{state | message_queue: message_queue |> :queue.drop()}}}
    end
  end

  @impl GenServer
  def handle_info(
        :flood_check,
        {socket,
         state = %__MODULE__{target: target, queue_flood_count: flood, channel_hashes: hashes}}
      )
      when flood > @flood_amount do
    socket |> disconnect(target, "Excess flood", hashes)
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
          socket
          |> message_send(%Sencha.Message{
            prefix: Application.fetch_env!(:sencha, :hostname),
            command: "NOTICE",
            middle: ["*"],
            trailing: "Found your hostname"
          })

          host

        {:error, _error} ->
          socket
          |> message_send(%Sencha.Message{
            prefix: Application.fetch_env!(:sencha, :hostname),
            command: "NOTICE",
            middle: ["*"],
            trailing: "Couldn't look up your hostname"
          })

          peer_ip |> :inet.ntoa() |> to_string
      end

    socket
    |> message_send(%Sencha.Message{
      prefix: Application.fetch_env!(:sencha, :hostname),
      command: "NOTICE",
      middle: ["*"],
      trailing: "Your hostname or IP address is " <> host
    })

    {:ok, connections} = gather()

    cond do
      length(connections) > @max_connections ->
        socket |> disconnect(%{host: host}, "Server is over capacity, please reconnect later", [])

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
  def handle_info({:remote_send, message}, {socket, state}) do
    socket |> message_send(message)

    {:noreply, {socket, state}}
  end

  @impl GenServer
  def handle_info(
        {:disconnect, reason},
        {socket, state = %__MODULE__{target: target, channel_hashes: hashes}}
      ) do
    socket |> disconnect(target, reason, hashes)

    {:noreply, {socket, state}}
  end

  @impl GenServer
  def handle_cast(
        {:check_kline, cidr, id, reason},
        {socket, state = %__MODULE__{target: target, channel_hashes: hashes}}
      ) do
    {:ok, {peer_ip, _peer_port}} = socket |> ThousandIsland.Socket.peername()

    if InetCidr.contains?(cidr, peer_ip) do
      socket
      |> message_send(__MODULE__.Numeric.encode(:ERR_YOUREBANNEDCREEP, target, %{}))
      |> disconnect(target, "Banned (##{id}) (#{reason})", hashes)
    end

    {:noreply, {socket, state}}
  end

  # ===========================================================================
  # Private functions
  # ===========================================================================
  defp message_recv(
         state = %__MODULE__{timeout_auth: timeout_auth},
         socket,
         message
       ) do
    Logger.debug(message)

    state =
      %__MODULE__{nick?: nick?, user?: user?, capabilities: caps_state} =
      state |> __MODULE__.Command.handle(socket, message)

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
        state |> __MODULE__.Welcome.send_burst(socket)

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
