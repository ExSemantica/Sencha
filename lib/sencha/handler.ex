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
              ident: "sencha",
              vhost: nil,
              connected?: false

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
      %Message{prefix: source, command: "NOTICE", params: [requested_handle], trailing: message}
      |> Message.encode()
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
      %Message{prefix: source, command: "PRIVMSG", params: [requested_handle], trailing: message}
      |> Message.encode()
    )

    {:noreply, {socket, state}, socket.read_timeout}
  end

  @impl GenServer
  def handle_info(:send_ping, {socket, state = %UserState{connected?: true}}) do
    socket
    |> ThousandIsland.Socket.send(
      %Message{command: "PING", trailing: ApplicationInfo.get_chat_hostname()}
      |> Message.encode()
    )

    {:noreply, {socket, state}, @ping_timeout}
  end

  # ===========================================================================
  # Data handling
  # ===========================================================================

  # ===========================================================================
  # Termination handling
  # ===========================================================================
  @impl ThousandIsland.Handler
  def handle_close(_socket, %UserState{connected?: true, user_process: user_process}) do
    Sencha.UserSupervisor.terminate_child(user_process)
  end

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
    |> ThousandIsland.Socket.send(%Message{command: "ERROR", trailing: reason} |> Message.encode())

    # Close the client socket, the handle_close callback will wipe the socket
    # from the User Supervisor
    socket |> ThousandIsland.Socket.close()

    # NOTE: Will this cause lingering states?
    {socket, state}
  end
end
