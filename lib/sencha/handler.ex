defmodule Sencha.Handler do
  @moduledoc """
  IRC-compatible TCP-based chat server.

  Users can log in with a nickname and password. There is no need for the USER
  command to be sent.
  """
  require Logger
  use ThousandIsland.Handler

  # Wait this long in milliseconds for NICK and PASS before disconnecting
  # Note that USER isn't implemented here
  @timeout_auth 5_000

  defmodule UserState do
    defstruct requested_handle: nil,
              irc_state: :performing_authentication,
              timeout_timer: nil,
              authentication_timer: nil,
              ident: "~Sencha",
              vhost: nil,
              connected?: false,
              capabilities: MapSet.new(),
              capabilities_ok?: false,
              sasl_data: "",
              sasl_streaming?: false

    def get_hostmask(s), do: "#{s.handle}!#{s.ident}@#{s.vhost}"
  end

  # ===========================================================================
  # Public calls
  # ===========================================================================
  def get_hostmask(pid), do: GenServer.call(pid, :get_hostmask)
  def get_username(pid), do: GenServer.call(pid, :get_username)

  def get_capabilities(pid), do: GenServer.call(pid, :get_capabilities)
  def put_capabilities(pid, caps), do: GenServer.cast(pid, {:put_capabilities, caps})

  def on_disconnect(pid, reason), do: GenServer.cast(pid, {:disconnect, reason})
  def on_already_present(pid, channel), do: GenServer.cast(pid, {:already_present, channel})
  def on_not_present(pid, channel), do: GenServer.cast(pid, {:not_present, channel})

  def on_join(pid, channel, hostmask), do: GenServer.cast(pid, {:join, channel, hostmask})

  def on_join(pid, channel, userlist, topic_info),
    do: GenServer.cast(pid, {:join, channel, userlist, topic_info})

  def on_part(pid, channel, hostmask, reason),
    do: GenServer.cast(pid, {:part, channel, hostmask, reason})

  def on_privmsg(pid, source, hostmask, message),
    do: GenServer.cast(pid, {:privmsg, source, hostmask, message})

  def on_quit(pid, hostmask, reason), do: GenServer.cast(pid, {:user_quit, hostmask, reason})
  # ===========================================================================
  # Initial connection
  # ===========================================================================
  @impl ThousandIsland.Handler
  def handle_connection(_socket, _state) do
    {:continue, %UserState{}, @timeout_auth}
  end

  # ===========================================================================
  # GenServer callbacks
  # ===========================================================================
  @impl GenServer
  def handle_call(
        :get_hostmask,
        _from,
        {socket, state}
      ) do
    {:reply, {:ok, state |> UserState.get_hostmask()}, {socket, state}, socket.read_timeout}
  end

  @impl GenServer
  def handle_call(
        :get_username,
        _from,
        {socket, state = %UserState{requested_handle: handle}}
      ) do
    {:reply, {:ok, handle}, {socket, state}, socket.read_timeout}
  end

  @impl GenServer
  def handle_call(
        :get_capabilities,
        _from,
        {socket, state = %UserState{capabilities: caps}}
      ) do
    {:reply, {:ok, caps}, {socket, state}, socket.read_timeout}
  end

  @impl GenServer
  def handle_cast(
        {:put_capabilities, caps},
        {socket, state}
      ) do
    {:noreply, {socket, %UserState{state | capabilities: caps}}, socket.read_timeout}
  end

  @impl GenServer
  def handle_cast({:disconnect, reason}, {socket, state}) do
    # Forces a disconnect from whoever. Please note this depends on the User
    # Pool to evict the user if they've succeeded connecting (CAP/SASL)

    # Notify the client of the connection termination
    socket
    |> ThousandIsland.Socket.send(
      %Sencha.Message{command: "ERROR", trailing: reason}
      |> Sencha.Message.encode()
    )

    {:stop, :normal, {socket, state}}
  end

  @impl GenServer
  def handle_cast(
        {:already_present, channel},
        {socket, state = %UserState{requested_handle: handle}}
      ) do
    socket
    |> Sencha.Numerics.send(443, nickname: handle, invitee: handle, recipient: channel)

    {:noreply, {socket, state}, socket.read_timeout}
  end

  @impl GenServer
  def handle_cast(
        {:not_present, channel},
        {socket, state = %UserState{requested_handle: handle}}
      ) do
    socket
    |> Sencha.Numerics.send(442, nickname: handle, recipient: channel)

    {:noreply, {socket, state}, socket.read_timeout}
  end

  @impl GenServer
  def handle_cast(
        {:join, channel, userlist, {topic, timestamp}},
        {socket, state = %UserState{requested_handle: handle}}
      ) do
    socket
    |> ThousandIsland.Socket.send(
      %Sencha.Message{
        prefix: state |> UserState.get_hostmask(),
        command: "JOIN",
        params: [channel]
      }
      |> Sencha.Message.encode()
    )

    socket
    |> Sencha.Numerics.send(332, nickname: handle, channel: channel, topic: topic)

    socket
    |> Sencha.Numerics.send(333,
      nickname: handle,
      channel: channel,
      set_by: "Services",
      set_at: timestamp
    )

    socket
    |> Sencha.Numerics.send(353,
      nickname: handle,
      channel: channel,
      users: userlist
    )

    socket
    |> Sencha.Numerics.send(366, nickname: handle, channel: channel)

    {:noreply, {socket, state}, socket.read_timeout}
  end

  @impl GenServer
  def handle_cast({:join, channel, hostmask}, {socket, state}) do
    socket
    |> ThousandIsland.Socket.send(
      %Sencha.Message{
        prefix: hostmask,
        command: "JOIN",
        params: [channel]
      }
      |> Sencha.Message.encode()
    )

    {:noreply, {socket, state}, socket.read_timeout}
  end

  @impl GenServer
  def handle_cast({:part, channel, hostmask, nil}, {socket, state}) do
    socket
    |> ThousandIsland.Socket.send(
      %Sencha.Message{
        prefix: hostmask,
        command: "PART",
        params: [channel]
      }
      |> Sencha.Message.encode()
    )

    {:noreply, {socket, state}, socket.read_timeout}
  end

  @impl GenServer
  def handle_cast({:part, channel, hostmask, reason}, {socket, state}) do
    socket
    |> ThousandIsland.Socket.send(
      %Sencha.Message{
        prefix: hostmask,
        command: "PART",
        params: [channel],
        trailing: reason
      }
      |> Sencha.Message.encode()
    )

    {:noreply, {socket, state}, socket.read_timeout}
  end

  @impl GenServer
  def handle_cast({:privmsg, source, hostmask, message}, {socket, state}) do
    socket
    |> ThousandIsland.Socket.send(
      %Sencha.Message{
        prefix: hostmask,
        command: "PRIVMSG",
        params: [source],
        trailing: message
      }
      |> Sencha.Message.encode()
    )

    {:noreply, {socket, state}, socket.read_timeout}
  end

  @impl GenServer
  def handle_cast({:user_quit, hostmask, nil}, {socket, state}) do
    socket
    |> ThousandIsland.Socket.send(
      %Sencha.Message{
        prefix: hostmask,
        command: "QUIT"
      }
      |> Sencha.Message.encode()
    )

    {:noreply, {socket, state}, socket.read_timeout}
  end

  @impl GenServer
  def handle_cast({:user_quit, hostmask, message}, {socket, state}) do
    socket
    |> ThousandIsland.Socket.send(
      %Sencha.Message{
        prefix: hostmask,
        command: "QUIT",
        trailing: message
      }
      |> Sencha.Message.encode()
    )

    {:noreply, {socket, state}, socket.read_timeout}
  end

  @impl GenServer
  def handle_cast(
        {:capabilities_set, new},
        {socket, state = %UserState{capabilities: old, requested_handle: handle}}
      ) do
    nick = handle || "*"

    supported = capabilities |> MapSet.intersection(__MODULE__.Cap.get_supported())

    if supported == old do
      # No capabilities got changed
      socket
      |> ThousandIsland.Socket.send(
        %Sencha.Message{
          prefix: Sencha.ApplicationInfo.get_chat_hostname(),
          command: "CAP",
          params: [nick, "NAK"],
          trailing: capabilities
        }
        |> Sencha.Message.encode()
      )

      {:noreply, {socket, state}, socket.read_timeout}
    else
      # Capabilities were changed
      socket
      |> ThousandIsland.Socket.send(
        %Sencha.Message{
          prefix: Sencha.ApplicationInfo.get_chat_hostname(),
          command: "CAP",
          params: [nick, "ACK"],
          trailing: supported |> Enum.join(" ")
        }
        |> Sencha.Message.encode()
      )

      {:noreply, {socket, %UserState{state | capabilities: supported, capabilities_ok?: true}},
       socket.read_timeout}
    end
  end

  @impl GenServer
  def handle_cast(:capabilities_info, {socket, state = %UserState{requested_handle: handle}}) do
    nick = handle || "*"

    socket
    |> ThousandIsland.Socket.send(
      %Sencha.Message{
        prefix: Sencha.ApplicationInfo.get_chat_hostname(),
        command: "CAP",
        params: [nick, "LS"],
        trailing: __MODULE__.Cap.get_supported() |> Enum.join(" ")
      }
      |> Sencha.Message.encode()
    )

    {:noreply, {socket, state}, socket.read_timeout}
  end

  @impl GenServer
  def handle_cast(
        {:capabilities_invalid, invalid},
        {socket, state = %UserState{requested_handle: handle}}
      ) do
    socket |> Sencha.Numerics.send(410, nickname: handle, capability: invalid)

    {:noreply, {socket, state}, socket.read_timeout}
  end

  @impl GenServer
  def handle_cast(
        :capabilities_ok,
        {socket, state = %UserState{requested_handle: handle, irc_state: :wait_for_cap_end}}
      ) do
    # IRC will connect since the capabilities handshake ended
    # This happens based on IRCv3 SASL and CAP specs
    case Sencha.UserPool.log_in(handle) do
      :ok ->
        state = %UserState{
          state
          | irc_state: :connected,
            connected?: true,
            vhost: "user/" <> handle
        }

        socket |> Sencha.Numerics.send_welcome(nickname: handle)

        {:noreply, {socket, state}, :infinity}

      {:error, {:already_started, _}} ->
        socket |> Sencha.Numerics.send(433, nickname: handle)
        on_disconnect(self(), "Account already in use")

        {:noreply, {socket, state}, socket.read_timeout}
    end
  end

  @impl GenServer
  def handle_cast(:capabilities_ok, {socket, state}) do
    {:noreply, {socket, %UserState{state | irc_state: :connected}}, socket.read_timeout}
  end

  @impl GenServer
  def handle_cast(:too_many_recipients, {socket, state = %UserState{requested_handle: handle}}) do
    socket |> Sencha.Numerics.send(407, nickname: handle)

    {:noreply, {socket, state}, socket.read_timeout}
  end

  # ===========================================================================
  # Message handling
  # ===========================================================================
  @impl GenServer
  def handle_info({:irc_message, message = %Sencha.Message{command: command}}, {socket, state}) do
    case command do
      "AUTHENTICATE" ->
        has_sasl? = state.capabilities_ok? and state.capabilities |> MapSet.member?("sasl")
        nick = state.requested_handle || "*"
        [sasl_data | _rest] = message.params

        cond do
          state.connected? ->
            socket |> Sencha.Numerics.send(907, nickname: nick)
            {:noreply, {socket, state}, socket.read_timeout}

          has_sasl? and state.sasl_streaming? and byte_size(sasl_data) > 400 ->
            socket |> Sencha.Numerics.send(905, nickname: nick)
            {:noreply, {socket, state}, socket.read_timeout}

          has_sasl? and state.sasl_streaming? and sasl_data == "*" ->
            socket |> Sencha.Numerics.send(906, nickname: nick)
            {:noreply, {socket, state}, socket.read_timeout}

          has_sasl? and state.sasl_streaming? and rem(byte_size(state.sasl_data), 400) == 0 and
              sasl_data == "+" ->
            try_sasl_authentication({socket, %UserState{state | sasl_streaming?: false}})

          has_sasl? and state.sasl_streaming? and rem(byte_size(sasl_data), 400) > 0 ->
            try_sasl_authentication(
              {socket,
               %UserState{
                 state
                 | sasl_streaming?: false,
                   sasl_data: state.sasl_data <> sasl_data
               }}
            )

          has_sasl? and state.sasl_streaming? ->
            {:noreply,
             {socket,
              %UserState{
                state
                | sasl_streaming?: false,
                  sasl_data: state.sasl_data <> sasl_data
              }}, socket.read_timeout}

          has_sasl? and sasl_data == "PLAIN" ->
            socket
            |> ThousandIsland.Socket.send(
              %Sencha.Message{
                command: "AUTHENTICATE",
                params: ["+"]
              }
              |> Sencha.Message.encode()
            )

            {:noreply,
             {socket,
              %UserState{
                state
                | sasl_streaming?: true
              }}, socket.read_timeout}

          has_sasl? ->
            socket |> Sencha.Numerics.send(908, nickname: nick)
            {:noreply, {socket, state}, socket.read_timeout}

          true ->
            {:noreply, {socket, state}, socket.read_timeout}
        end

      "CAP" ->
        __MODULE__.Cap.handle(self(), message, socket)
        {:noreply, {socket, state}, socket.read_timeout}

      "PONG" ->
        __MODULE__.Pong.handle(self(), message, socket)
        {:noreply, {socket, state}, socket.read_timeout}

      "PING" ->
        __MODULE__.Ping.handle(self(), message, socket)
        {:noreply, {socket, state}, socket.read_timeout}

      "PRIVMSG" when state.connected? ->
        __MODULE__.Privmsg.handle(self(), message, socket)
        {:noreply, {socket, state}, socket.read_timeout}

      "JOIN" when state.connected? ->
        __MODULE__.Join.handle(self(), message, socket)
        {:noreply, {socket, state}, socket.read_timeout}

      "PART" when state.connected? ->
        __MODULE__.Part.handle(self(), message, socket)
        {:noreply, {socket, state}, socket.read_timeout}

      "QUIT" when is_nil(message.trailing) ->
        Logger.debug("Quit", socket_pid: self())
        Sencha.UserPool.log_out(state.requested_handle, "Quit")
        {:noreply, {socket, state}, socket.read_timeout}

      "QUIT" ->
        Logger.debug("Quit (#{message.trailing})", socket_pid: self())
        Sencha.UserPool.log_out(state.requested_handle, "Quit: #{message.trailing}")
        {:noreply, {socket, state}, socket.read_timeout}

      _message ->
        {:noreply, {socket, state}, socket.read_timeout}
    end
  end

  # ===========================================================================
  # Data handling
  # ===========================================================================
  @impl ThousandIsland.Handler
  def handle_data(data, socket, state) do
    # Decode all received messages
    data
    |> Sencha.Message.decode()
    |> Stream.each(fn message -> send(self(), {:irc_message, message}) end)
    |> Stream.run()

    {:continue, state, socket.read_timeout}
  end

  # ===========================================================================
  # Termination handling
  # ===========================================================================
  @impl ThousandIsland.Handler
  def handle_timeout(_socket, _state) do
    on_disconnect(self(), "Authentication timeout")

    :ok
  end

  @impl ThousandIsland.Handler
  def handle_error(_reason, _socket, %UserState{requested_handle: handle}) do
    if is_nil(handle) do
      on_disconnect(self(), "Server error")
    else
      Sencha.UserPool.log_out(handle, "Server error")
    end

    :ok
  end

  @impl ThousandIsland.Handler
  def handle_shutdown(_socket, %UserState{requested_handle: handle}) do
    if is_nil(handle) do
      on_disconnect(self(), "Server shutting down")
    else
      Sencha.UserPool.log_out(handle, "Server shutting down")
    end

    :ok
  end

  # ===========================================================================
  # Private functions
  # ===========================================================================
  defp try_sasl_authentication({socket, state = %UserState{sasl_data: sasl_data}}) do
    {:ok, decoded} = Base.decode64(sasl_data)
    split = decoded |> String.split("\x00")

    user_info =
      case split do
        [_authzid, authcid, password] -> lookup_via_gateway(authcid, password)
        _ -> {:error, :bad_sasl_data}
      end

    case user_info do
      {:ok, %{username: handle}} ->
        Logger.debug("#{handle} logs in", socket_pid: self())

        new_state = %Sencha.Handler.UserState{
          state
          | requested_handle: handle,
            vhost: "user/#{handle}",
            irc_state: :wait_for_cap_end,
            sasl_data: :redacted
        }

        socket
        |> Sencha.Numerics.send(900,
          nickname: handle,
          hostmask: new_state |> UserState.get_hostmask()
        )

        socket
        |> Sencha.Numerics.send(903, nickname: handle)

        {:noreply, {socket, new_state}, socket.read_timeout}

      {:error, error} ->
        Logger.debug("Client fails to authenticate: #{inspect(error)}", socket_pid: self())

        socket
        |> Sencha.Numerics.send(904, [])

        {:noreply, {socket, state}, socket.read_timeout}
    end
  end

  defp lookup_via_gateway(username, password) do
    # Look for nearest gateway
    fastest_node = Sencha.Gateway.fastest_node()

    # Try to get info from the nearest gateway
    if is_nil(fastest_node) do
      {:error, :no_gateway}
    else
      Sencha.Gateway.user_info(fastest_node, self(), username, password)

      receive do
        {Exsemantica.Gateway, ^fastest_node, {:user_info, {:ok, info}}} ->
          {:ok, info}

        {Exsemantica.Gatewat, ^fastest_node, {:user_info, {:error, what}}} ->
          {:error, what}
      after
        5000 ->
          {:error, :gateway_timeout}
      end
    end
  end
end
