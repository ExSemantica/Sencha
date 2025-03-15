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
  @timeout_auth 10_000

  # Ping interval in milliseconds
  @ping_interval 15_000

  # Ping timeout in milliseconds
  @ping_timeout 5_000

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
              sasl_method: nil,
              sasl_data: nil,
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

  # ===========================================================================
  # Initial connection
  # ===========================================================================
  @impl ThousandIsland.Handler
  def handle_connection(_socket, _state) do
    {:continue, %UserState{}, {:persistent, @timeout_auth}}
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

    {:noreply,
     {socket,
      %UserState{
        state
        | timeout_timer: Process.send_after(self(), :ping_timeout, @ping_timeout)
      }}, socket.read_timeout}
  end

  @impl GenServer
  def handle_info(:ping_timeout, socket_state = {socket, state}) do
    socket_state
    |> quit(
      "Ping timeout (#{DateTime.utc_now(:second) |> DateTime.diff(state.last_ping, :second)} seconds)"
    )

    {:noreply, socket_state, socket.read_timeout}
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
         connected?: true,
         ping_received?: true,
         ping_timer: ping_timer,
         timeout_timer: timeout_timer
       }} ->
        if not is_nil(ping_timer), do: Process.cancel_timer(ping_timer)
        if not is_nil(timeout_timer), do: Process.cancel_timer(timeout_timer)

        {:continue,
         %__MODULE__.UserState{
           state
           | ping_received?: false,
             ping_timer: Process.send_after(self(), :ping, @ping_interval),
             timeout_timer: nil,
             last_ping: DateTime.utc_now(:second)
         }, {:persistent, :infinity}}

      {_socket, state} when state.connected? ->
        {:continue, state, {:persistent, :infinity}}

      {_socket, state} ->
        {:continue, state, socket.read_timeout}
    end
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

      Sencha.UserSupervisor.terminate_child(user_process)
    end

    :ok
  end

  @impl ThousandIsland.Handler
  def handle_error(_reason, socket, state) do
    {socket, state} |> quit("Server error")

    :ok
  end

  @impl ThousandIsland.Handler
  def handle_shutdown(socket, state) do
    {socket, state} |> quit("Server is shutting down")

    :ok
  end

  def check_for_others({socket, state}, handle) do
    user_status = Sencha.UserSupervisor.start_child(handle, socket)

    case user_status do
      {:ok, user_pid} ->
        Logger.debug("#{handle} connects")

        {:cont,
         {socket,
          %UserState{
            state
            | irc_state: :connected,
              connected?: true,
              requested_handle: handle,
              ping_received?: true,
              user_process: user_pid
          }}
         |> Sencha.Handler.Welcome.send_burst()}

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

        {socket, state} |> Sencha.Handler.quit("Account already in use")

        {:halt, {socket, state}}
    end
  end

  def quit({socket, state = %UserState{user_process: user_process}}, reason) do
    if Process.alive?(user_process) do
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
  # Private calls
  # ===========================================================================
  defp handle_while(message = %Sencha.Message{command: "CAP"}, socket_state) do
    __MODULE__.Cap.handle(message, socket_state)
  end

  defp handle_while(message = %Sencha.Message{command: "PONG"}, socket_state) do
    __MODULE__.Pong.handle(message, socket_state)
  end

  defp handle_while(message = %Sencha.Message{command: "PING"}, socket_state) do
    __MODULE__.Ping.handle(message, socket_state)
  end

  defp handle_while(message = %Sencha.Message{command: "PRIVMSG"}, socket_state) do
    __MODULE__.Privmsg.handle(message, socket_state)
  end

  defp handle_while(message = %Sencha.Message{command: "JOIN"}, socket_state) do
    __MODULE__.Join.handle(message, socket_state)
  end

  defp handle_while(message = %Sencha.Message{command: "PART"}, socket_state) do
    __MODULE__.Part.handle(message, socket_state)
  end

  defp handle_while(%Sencha.Message{command: "NICK"}, socket_state) do
    {:cont, socket_state}
  end

  defp handle_while(%Sencha.Message{command: "USER"}, socket_state) do
    {:cont, socket_state}
  end

  defp handle_while(%Sencha.Message{command: "PASS"}, socket_state) do
    {:cont, socket_state}
  end

  defp handle_while(
         message = %Sencha.Message{command: "AUTHENTICATE"},
         socket_state = {_socket, state = %UserState{capabilities: capabilities}}
       ) do
    if state.capabilities_ok? and capabilities |> MapSet.member?("sasl") do
      # We have SASL enabled and we gave a CAP END, proceed...
      __MODULE__.Authenticate.handle(message, socket_state)
    else
      {:cont, socket_state}
    end
  end

  defp handle_while(%Sencha.Message{command: "QUIT", trailing: nil}, socket_state) do
    {:halt, socket_state |> quit("Client quit")}
  end

  defp handle_while(%Sencha.Message{command: "QUIT", trailing: reason}, socket_state) do
    {:halt, socket_state |> quit("Client quit: " <> reason)}
  end

  defp handle_while(message, socket_state) do
    Logger.debug("Unimplemented IRC message: #{inspect(message)}")
    {:cont, socket_state}
  end
end
