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

  # Ping interval in milliseconds
  @ping_interval 15_000

  # Ping timeout in milliseconds
  @ping_timeout 5_000

  @regex_ctcp_action ~r/\x01ACTION (?<action>.+)\x01/

  defmodule UserState do
    defstruct requested_handle: nil,
              irc_state: :performing_authentication,
              ping_timer: nil,
              timeout_timer: nil,
              authentication_timer: nil,
              user_process: nil,
              ident: "~Sencha",
              vhost: nil,
              connected?: false,
              ping_received?: false,
              last_ping: nil,
              capabilities: MapSet.new(),
              capabilities_ok?: false,
              sasl_data: "",
              sasl_streaming?: false

    def get_host_mask(%__MODULE__{requested_handle: handle, ident: ident, vhost: vhost}) do
      handle <> "!" <> ident <> "@" <> vhost
    end
  end

  # ===========================================================================
  # Public calls
  # ===========================================================================
  @doc """
  Terminates the specified PID's connection, usually by an administrator.
  """
  def kill_client(pid, source, reason) do
    GenServer.cast(pid, {:kill_client, source, reason})
  end

  @doc """
  Sends a notice to the specified PID's connection.
  """
  def recv_notice(pid, source, message) do
    GenServer.cast(pid, {:recv_notice, source, message})
  end

  @doc """
  Sends a private message to the specified PID's connection.
  """
  def recv_privmsg(pid, source, message) do
    GenServer.cast(pid, {:recv_privmsg, source, message})
  end

  @doc """
  Gets this socket's state variable.
  """
  def get_state(pid) do
    GenServer.call(pid, :get_state)
  end

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
  def handle_call(:get_state, _from, {socket, state}) do
    {:reply, {:ok, state}, {socket, state}, socket.read_timeout}
  end

  @impl GenServer
  def handle_cast({:kill_client, source, reason}, {socket, state}) do
    {:noreply, {socket, state} |> quit("Killed (#{source} (#{reason}))"), socket.read_timeout}
  end

  @impl GenServer
  def handle_cast(
        {:recv_notice, source, message},
        {socket, state = %UserState{connected?: true, requested_handle: requested_handle}}
      ) do
    socket
    |> ThousandIsland.Socket.send(
      %Sencha.Message{
        prefix: source,
        command: "NOTICE",
        params: [requested_handle],
        trailing: message
      }
      |> Sencha.Message.encode()
    )

    {:noreply, {socket, state}, socket.read_timeout}
  end

  @impl GenServer
  def handle_cast(
        {:recv_privmsg, source, message},
        {socket, state = %UserState{connected?: true, requested_handle: requested_handle}}
      ) do
    socket
    |> ThousandIsland.Socket.send(
      %Sencha.Message{
        prefix: source,
        command: "PRIVMSG",
        params: [requested_handle],
        trailing: message
      }
      |> Sencha.Message.encode()
    )

    {:noreply, {socket, state}, socket.read_timeout}
  end

  # ===========================================================================
  # Message handling
  # ===========================================================================
  @impl GenServer
  def handle_info(:ping, {socket, state = %UserState{connected?: true}}) do
    socket
    |> ThousandIsland.Socket.send(
      %Sencha.Message{prefix: Sencha.ApplicationInfo.get_chat_hostname(), command: "PING"}
      |> Sencha.Message.encode()
    )

    {:noreply,
     {socket,
      %UserState{
        state
        | timeout_timer: Process.send_after(self(), :ping_timeout, @ping_timeout)
      }}, socket.read_timeout}
  end

  @impl GenServer
  def handle_info(:ping_acknowledged, {socket, state = %UserState{connected?: true}}) do
    # Elixir won't raise an error if the timers aren't active...
    Process.cancel_timer(state.ping_timer)
    Process.cancel_timer(state.timeout_timer)

    {:noreply,
     {socket,
      %UserState{
        state
        | ping_timer: Process.send_after(self(), :ping, @ping_interval),
          timeout_timer: nil,
          last_ping: DateTime.utc_now(:second)
      }}, socket.read_timeout}
  end

  @impl GenServer
  def handle_info(:ping_timeout, {socket, state}) do
    {socket, state}
    |> quit(
      "Ping timeout (#{DateTime.utc_now(:second) |> DateTime.diff(state.last_ping, :second)} seconds)"
    )

    {:noreply, {socket, state}, socket.read_timeout}
  end

  @impl GenServer
  def handle_info(
        {:capabilities_set, new},
        {socket, state = %UserState{capabilities: old, requested_handle: handle}}
      ) do
    nick = handle || "*"

    # Disable these IRCv3 extensions
    disabled =
      new
      |> Enum.filter(&(String.first(&1) == "-"))
      |> Enum.map(&String.replace_prefix(&1, "-", ""))
      |> MapSet.new()

    # Enable these ones and join them with the old set of IRCv3 extensions when 
    # initially enabled
    capabilities =
      new
      |> Enum.filter(&(String.first(&1) != "-"))
      |> MapSet.new()
      |> MapSet.union(old)
      |> MapSet.difference(disabled)

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
  def handle_info(:capabilities_info, {socket, state = %UserState{requested_handle: handle}}) do
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
  def handle_info(
        {:capabilities_invalid, invalid},
        {socket, state = %UserState{requested_handle: handle}}
      ) do
    nick = handle || "*"

    socket
    |> ThousandIsland.Socket.send(
      %Sencha.Message{
        prefix: Sencha.ApplicationInfo.get_chat_hostname(),
        command: "410",
        params: [nick, invalid],
        trailing: "Invalid CAP command"
      }
      |> Sencha.Message.encode()
    )

    {:noreply, {socket, state}, socket.read_timeout}
  end

  @impl GenServer
  def handle_info(
        :capabilities_ok,
        {socket, state = %UserState{requested_handle: handle, irc_state: :wait_for_cap_end}}
      ) do
    # IRC will connect since the capabilities handshake ended
    # This happens based on IRCv3 SASL and CAP specs
    case Sencha.UserSupervisor.start_child(handle, self()) do
      {:ok, user_pid} ->
        Logger.debug("#{handle} connects")

        {:noreply,
         {socket,
          %UserState{
            state
            | irc_state: :connected,
              connected?: true,
              ping_received?: true,
              user_process: user_pid
          }}
         |> Sencha.Welcome.send_burst(), :infinity}

      {:error, {:already_started, _}} ->
        socket
        |> ThousandIsland.Socket.send(
          %Sencha.Message{
            prefix: Sencha.ApplicationInfo.get_chat_hostname(),
            command: "433",
            params: [handle],
            trailing: "Account already in use"
          }
          |> Sencha.Message.encode()
        )

        {:noreply, {socket, state} |> quit("Account already in use"), socket.read_timeout}
    end
  end

  @impl GenServer
  def handle_info(:capabilities_ok, {socket, state}) do
    {:noreply, {socket, %UserState{state | irc_state: :connected}}, socket.read_timeout}
  end

  def handle_info(:too_many, {socket, state = %UserState{requested_handle: handle}}) do
    socket
    |> ThousandIsland.Socket.send(
      %Sencha.Message{
        prefix: Sencha.ApplicationInfo.get_chat_hostname(),
        command: "407",
        params: [handle],
        trailing: "Too many recipients"
      }
      |> Sencha.Message.encode()
    )

    {:noreply, {socket, state}, socket.read_timeout}
  end

  @impl GenServer
  def handle_info({:message_these, recipients, message}, {socket, state}) do
    {:noreply, {socket, state} |> direct_message(recipients, message), socket.read_timeout}
  end

  @impl GenServer
  def handle_info({:join_these, recipients}, {socket, state}) do
    {:noreply, {socket, state} |> join(recipients), socket.read_timeout}
  end

  @impl GenServer
  def handle_info({:part_these, recipients, reason}, {socket, state}) do
    {:noreply, {socket, state} |> part(recipients, reason), socket.read_timeout}
  end

  @impl GenServer
  def handle_info({:irc_message, message = %Sencha.Message{command: command}}, {socket, state}) do
    case command do
      "AUTHENTICATE" ->
        has_sasl? = state.capabilities_ok? and state.capabilities |> MapSet.member?("sasl")
        nick = state.requested_handle || "*"
        [sasl_data | _rest] = message.params

        cond do
          state.connected? ->
            socket
            |> ThousandIsland.Socket.send(
              %Sencha.Message{
                prefix: Sencha.ApplicationInfo.get_chat_hostname(),
                command: "907",
                params: [nick],
                trailing: "You have already authenticated using SASL"
              }
              |> Sencha.Message.encode()
            )

            {:noreply, {socket, state}, socket.read_timeout}

          has_sasl? and state.sasl_streaming? and byte_size(sasl_data) > 400 ->
            socket
            |> ThousandIsland.Socket.send(
              %Sencha.Message{
                prefix: Sencha.ApplicationInfo.get_chat_hostname(),
                command: "905",
                params: [nick],
                trailing: "SASL message too long"
              }
              |> Sencha.Message.encode()
            )

            {:noreply, {socket, state}, socket.read_timeout}

          has_sasl? and state.sasl_streaming? and sasl_data == "*" ->
            socket
            |> ThousandIsland.Socket.send(
              %Sencha.Message{
                prefix: Sencha.ApplicationInfo.get_chat_hostname(),
                command: "906",
                params: [nick],
                trailing: "SASL authentication aborted"
              }
              |> Sencha.Message.encode()
            )

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
            socket
            |> ThousandIsland.Socket.send(
              %Sencha.Message{
                prefix: Sencha.ApplicationInfo.get_chat_hostname(),
                command: "908",
                params: [nick, "PLAIN"],
                trailing: "are available SASL mechanisms"
              }
              |> Sencha.Message.encode()
            )

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
        Logger.debug("Client quit", socket_pid: self())
        {socket, state} |> quit("Client quit")
        {:noreply, {socket, state}, socket.read_timeout}

      "QUIT" ->
        Logger.debug("Client quit (#{message.trailing})", socket_pid: self())
        {socket, state} |> quit("Client quit: " <> message.trailing)
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
  def handle_timeout(socket, state) do
    {socket, state} |> quit("Authentication timeout")

    :ok
  end

  @impl ThousandIsland.Handler
  def handle_close(_socket, %UserState{user_process: nil}), do: :ok

  @impl ThousandIsland.Handler
  def handle_close(socket, state = %UserState{user_process: user_process}) do
    # This is complicated so I will explain how this all works
    if Process.alive?(user_process) do
      reason = Sencha.User.get_quit_reason(user_process)

      Logger.debug("#{user_process |> Sencha.User.get_handle()} disconnects (#{reason})")

      receivers =
        user_process
        # Get a list of channels the user is connected to
        |> Sencha.User.get_channels()
        # Get a list of all sockets in all channels the user is in
        |> Enum.map(fn channel ->
          channel |> Sencha.Channel.quit({socket, state})
          others = channel |> Sencha.Channel.get_users()

          for {other_socket, _other_pid} <- others do
            other_socket
          end
        end)
        # We need to flatten it since it's a list of lists
        |> List.flatten()
        # Remove duplicates
        |> MapSet.new()
        # Convert to a list
        |> MapSet.to_list()

      for receiver <- receivers do
        receiver
        |> ThousandIsland.Socket.send(
          %Sencha.Message{
            prefix: state |> UserState.get_host_mask(),
            command: "QUIT",
            trailing: reason
          }
          |> Sencha.Message.encode()
        )
      end
    end
    Sencha.UserSupervisor.terminate_child(user_process)

    :ok
  end

  @impl ThousandIsland.Handler
  def handle_error(_reason, socket, state) do
    {socket, state} |> quit("Server initiated disconnect")

    :ok
  end

  @impl ThousandIsland.Handler
  def handle_shutdown(socket, state) do
    {socket, state} |> quit("Server is shutting down")

    :ok
  end

  def quit({socket, state = %UserState{user_process: user_process}}, reason) do
    if not is_nil(user_process) and Process.alive?(user_process) do
      Sencha.User.set_quit_reason(user_process, reason)
    end

    # Notify the client of the connection termination
    socket
    |> ThousandIsland.Socket.send(
      %Sencha.Message{command: "ERROR", trailing: reason}
      |> Sencha.Message.encode()
    )

    # Close the client socket, the handle_close callback will wipe the socket
    # from the User Supervisor
    socket |> ThousandIsland.Socket.close()

    # NOTE: Will this cause lingering states?
    {socket, state}
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

        host = Sencha.ApplicationInfo.get_chat_hostname()

        new_state = %Sencha.Handler.UserState{
          state
          | requested_handle: handle,
            vhost: "user/#{handle}",
            irc_state: :wait_for_cap_end,
            sasl_data: :redacted
        }

        burst = [
          %Sencha.Message{
            prefix: host,
            command: "900",
            params: [handle, new_state |> Sencha.Handler.UserState.get_host_mask(), handle],
            trailing: "You are now logged in as #{handle}"
          },
          %Sencha.Message{
            prefix: host,
            command: "903",
            params: [handle],
            trailing: "SASL authentication successful"
          }
        ]

        for b <- burst do
          socket |> ThousandIsland.Socket.send(b |> Sencha.Message.encode())
        end

        {:noreply, {socket, new_state}, :infinity}

      {:error, error} ->
        Logger.debug("Client fails to authenticate: #{inspect(error)}", socket_pid: self())

        socket
        |> ThousandIsland.Socket.send(
          %Sencha.Message{
            prefix: Sencha.ApplicationInfo.get_chat_hostname(),
            command: "904",
            params: ["*"],
            trailing: "SASL authentication failed"
          }
          |> Sencha.Message.encode()
        )

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

  defp direct_message({socket, state}, [], _message) do
    {socket, state}
  end

  defp direct_message(
         {socket, state = %UserState{requested_handle: handle}},
         [recipient | recipients],
         message
       ) do
    if recipient |> String.starts_with?("#") do
      case Registry.lookup(Sencha.ChannelRegistry, recipient) do
        [{pid, _}] ->
          Sencha.Channel.talk(pid, {socket, state}, message)
          format_message(recipient, handle, message)

        [] ->
          socket
          |> ThousandIsland.Socket.send(
            %Sencha.Message{
              prefix: Sencha.ApplicationInfo.get_chat_hostname(),
              command: "403",
              params: [handle, recipient],
              trailing: "No such aggregate"
            }
            |> Sencha.Message.encode()
          )
      end
    else
      case Registry.lookup(Sencha.UserRegistry, recipient) do
        [{pid, _}] ->
          Sencha.User.send(pid, {socket, state}, message)
          format_message(recipient, handle, message)

        [] ->
          socket
          |> ThousandIsland.Socket.send(
            %Sencha.Message{
              prefix: Sencha.ApplicationInfo.get_chat_hostname(),
              command: "401",
              params: [handle, recipient],
              trailing: "No such user"
            }
            |> Sencha.Message.encode()
          )
      end
    end

    direct_message({socket, state}, recipients, message)
  end

  defp join({socket, state}, []) do
    {socket, state}
  end

  defp join({socket, state = %UserState{requested_handle: handle}}, [recipient | recipients]) do
    case Sencha.ChannelSupervisor.start_child(recipient) do
      {:ok, pid} ->
        Logger.debug("#{handle} joins channel #{recipient}", socket_pid: self())
        Sencha.Channel.join(pid, {socket, state})

      {:error, {:already_started, pid}} ->
        Logger.debug("#{handle} joins channel #{recipient}", socket_pid: self())
        Sencha.Channel.join(pid, {socket, state})

      {:error, :no_such_item} ->
        socket
        |> ThousandIsland.Socket.send(
          %Sencha.Message{
            prefix: Sencha.ApplicationInfo.get_chat_hostname(),
            command: "403",
            params: [handle, recipient],
            trailing: "No such aggregate"
          }
          |> Sencha.Message.encode()
        )
    end

    join({socket, state}, recipients)
  end

  defp part({socket, state}, [], _reason) do
    {socket, state}
  end

  defp part(
         {socket, state = %UserState{requested_handle: handle}},
         [recipient | recipients],
         reason
       ) do
    case Registry.lookup(Sencha.ChannelRegistry, recipient) do
      [{pid, _}] ->
        Logger.debug("#{handle} leaves channel #{recipient} (#{reason})")
        Sencha.Channel.part(pid, {socket, state}, reason)

      [] ->
        socket
        |> ThousandIsland.Socket.send(
          %Sencha.Message{
            prefix: Sencha.ApplicationInfo.get_chat_hostname(),
            command: "403",
            params: [handle, recipient],
            trailing: "No such aggregate"
          }
          |> Sencha.Message.encode()
        )
    end

    part({socket, state}, recipients, reason)
  end

  defp format_message(recipient, handle, message) do
    if message =~ @regex_ctcp_action do
      converted = Regex.named_captures(@regex_ctcp_action, message)
      Logger.debug("[#{recipient}] * #{handle} #{converted["action"]}", socket_pid: self())
    else
      Logger.debug("[#{recipient}] <#{handle}> #{message}", socket_pid: self())
    end
  end
end
