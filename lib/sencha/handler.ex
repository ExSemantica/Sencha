defmodule Sencha.Handler do
  @moduledoc """
  IRC-compatible TCP-based chat server.

  Users can log in with a nickname and password. There is no need for the USER
  command to be sent.
  """
  alias Sencha.ApplicationInfo
  alias Sencha.Message
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
              requested_password: nil,
              irc_state: :performing_authentication,
              ping_timer: nil,
              authentication_timer: nil,
              user_process: nil,
              ident: "~Sencha",
              vhost: nil,
              connected?: false,
              ping_received?: false

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

  @impl GenServer
  def handle_info(:ping, {socket, state = %UserState{connected?: true}}) do
    socket
    |> ThousandIsland.Socket.send(
      %Sencha.Message{prefix: Sencha.ApplicationInfo.get_chat_hostname(), command: "PING"}
      |> Sencha.Message.encode()
    )

    {:noreply, {socket, state}, socket.read_timeout}
  end

  # ===========================================================================
  # Data handling
  # ===========================================================================
  @impl ThousandIsland.Handler
  def handle_data(data, socket, state) do
    # Decode all received messages
    messages = data |> Sencha.Message.decode()

    reduced = messages |> Enum.reduce_while({socket, state}, &handle_while/2)

    case reduced do
      {_socket,
       state = %__MODULE__.UserState{
         irc_state: :authentication_ready,
         requested_handle: handle,
         requested_password: password
       }} ->
        # TODO: error cases
        info = lookup_via_gateway(handle, password)
        host = Sencha.ApplicationInfo.get_chat_hostname()

        case info do
          {:ok, %{username: real_handle}} ->
            user_status = Sencha.UserSupervisor.start_child(real_handle, self())

            case user_status do
              {:ok, user_status_pid} ->
                Logger.debug("#{real_handle} connects")

                refreshed =
                  Sencha.ApplicationInfo.get_last_refreshed()
                  |> Calendar.strftime("%a, %-d %b %Y %X %Z")

                user_status_pid |> Sencha.User.set_modes(["+w"])

                version = Sencha.ApplicationInfo.get_version()

                burst = [
                  %Sencha.Message{
                    prefix: host,
                    command: "001",
                    params: [real_handle],
                    trailing: "Welcome to Sencha, " <> real_handle
                  },
                  %Sencha.Message{
                    prefix: host,
                    command: "002",
                    params: [real_handle],
                    trailing: "Your host is " <> host <> ", running version v" <> version
                  },
                  %Sencha.Message{
                    prefix: host,
                    command: "003",
                    params: [real_handle],
                    trailing: "This server was last restarted " <> refreshed
                  },
                  %Sencha.Message{
                    prefix: host,
                    command: "004",
                    params: [real_handle, "sencha", version]
                  },
                  %Sencha.Message{
                    prefix: host,
                    command: "422",
                    params: [real_handle],
                    trailing: "MOTD File is unimplemented"
                  }
                ]

                for b <- burst do
                  socket |> ThousandIsland.Socket.send(b |> Sencha.Message.encode())
                end

                {:continue,
                 %__MODULE__.UserState{
                   state
                   | irc_state: :connected,
                     connected?: true,
                     requested_handle: real_handle,
                     requested_password: nil,
                     ping_received?: false,
                     ping_timer: Process.send_after(self(), :ping, @ping_interval),
                     user_process: user_status_pid
                 }, @ping_interval + @ping_timeout}

              {:error, {:already_started, _}} ->
                socket
                |> ThousandIsland.Socket.send(
                  %Sencha.Message{
                    prefix: host,
                    command: "433",
                    params: [real_handle],
                    trailing: "Nickname is already in use"
                  }
                  |> Sencha.Message.encode()
                )

                {socket, state} |> quit("Nickname is already in use")
                {:close, state}

              {:error, :max_children} ->
                {socket, state} |> quit("Too many users logged in to this server")
                {:close, state}
            end

          {:error, :authentication_failed} ->
            {socket, state} |> quit("Authentication failed")
            {:close, state}

          {:error, :no_such_item} ->
            {socket, state} |> quit("Invalid user")
            {:close, state}

          {:error, :no_gateway} ->
            {socket, state} |> quit("No gateway available to handle user information")
            {:close, state}

          {:error, :gateway_timeout} ->
            {socket, state} |> quit("User information gateway timeout")
            {:close, state}
        end

      {_socket, state = %__MODULE__.UserState{ping_received?: true, ping_timer: ping_timer}} ->
        if not is_nil(ping_timer), do: Process.cancel_timer(ping_timer)

        {:continue,
         %__MODULE__.UserState{
           state
           | ping_received?: false,
             ping_timer: Process.send_after(self(), :ping, @ping_interval)
         }, @ping_interval + @ping_timeout}

      {socket, state} ->
        {:continue, state, socket.read_timeout}
    end
  end

  # ===========================================================================
  # Termination handling
  # ===========================================================================
  @impl ThousandIsland.Handler
  def handle_timeout(socket, state = %__MODULE__.UserState{irc_state: irc_state}) do
    case irc_state do
      :connected -> {socket, state} |> quit("Ping timeout")
      :performing_authentication -> {socket, state} |> quit("Authentication timeout")
    end
  end

  @impl ThousandIsland.Handler
  def handle_close(_socket, %UserState{connected?: true, user_process: user_process}) do
    if Process.alive?(user_process) do
      Sencha.UserSupervisor.terminate_child(user_process)
    end
  end

  @impl ThousandIsland.Handler
  def handle_shutdown(socket, state) do
    {socket, state} |> quit("Server has shut down")
  end

  # ===========================================================================
  # Private calls
  # ===========================================================================
  defp quit(
         {socket, state = %UserState{user_process: user_process, ping_timer: ping_timer}},
         reason
       ) do
    # This is complicated so I will explain how this all works
    if Process.alive?(user_process) do
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
          %Message{prefix: state |> UserState.get_host_mask(), command: "QUIT", trailing: reason}
          |> Message.encode()
        )
      end

      :ok = Sencha.UserSupervisor.terminate_child(user_process)

      # Ping timer should be removed when the connection is removed
      if not is_nil(ping_timer), do: Process.cancel_timer(ping_timer)
    end

    # Notify the client of the connection termination
    socket
    |> ThousandIsland.Socket.send(
      %Message{command: "ERROR", trailing: reason}
      |> Message.encode()
    )

    # Close the client socket, the handle_close callback will wipe the socket
    # from the User Supervisor
    socket |> ThousandIsland.Socket.close()
    socket |> ThousandIsland.Socket.shutdown(:read_write)

    # NOTE: Will this cause lingering states?
    {socket, state}
  end

  defp handle_while(message = %Sencha.Message{command: "PASS"}, socket_state) do
    __MODULE__.Pass.handle(message, socket_state)
  end

  defp handle_while(message = %Sencha.Message{command: "NICK"}, socket_state) do
    __MODULE__.Nick.handle(message, socket_state)
  end

  defp handle_while(message = %Sencha.Message{command: "PONG"}, socket_state) do
    __MODULE__.Pong.handle(message, socket_state)
  end

  defp handle_while(message = %Sencha.Message{command: "PING"}, socket_state) do
    __MODULE__.Ping.handle(message, socket_state)
  end

  defp handle_while(%Sencha.Message{command: "QUIT", trailing: reason}, socket_state) do
    {:halt, socket_state |> quit("Client quit: " <> reason)}
  end


  defp handle_while(message, socket_state) do
    Logger.debug("Unimplemented IRC message: #{inspect(message)}")
    {:cont, socket_state}
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
