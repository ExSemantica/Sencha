defmodule Sencha.Handler do
  @moduledoc """
  IRC-compatible TCP-based chat server.

  Users can log in with a nickname and password. There is no need for the USER
  command to be sent.
  """
  require Logger
  use ThousandIsland.Handler

  # ===========================================================================
  # Public callbacks
  # ===========================================================================
  @doc """
  Disconnects this socket from IRC gracefully using an ERROR packet.

  You should specify a reason string when disconnecting the socket.
  """
  def disconnect(pid, reason), do: GenServer.cast(pid, {:disconnect, reason})

  @doc """
  Acknowledges this socket's IRCv3 capabilities.
  - The delta is a string of added and removed capabilities.
  """
  def capabilities_request(pid, delta),
    do: GenServer.cast(pid, {:capabilities_request, delta})

  @doc """
  Stops the capability negotiation process.
  """
  def capabilities_end(pid), do: GenServer.cast(pid, :capabilities_end)

  @doc """
  Handles a PLAIN authentication.
  """
  def authentication_put(pid, data), do: GenServer.cast(pid, {:authentication_put, data})

  # ===========================================================================
  # GenServer callbacks
  # ===========================================================================
  @impl GenServer
  def handle_cast({:disconnect, reason}, {socket, state}) do
    # Notify them that their connection has been terminated
    socket
    |> perform_close(reason)

    # Stop this client process
    {:stop, :normal, {socket, state}}
  end

  @impl GenServer
  def handle_cast(
        {:capabilities_request, delta_string},
        {socket,
         state = %__MODULE__.UserState{
           capabilities: capabilities_old,
           authentication_state: auth_state,
           nickname: nickname
         }}
      ) do
    # What nickname do I currently have, or if nil default to '*'
    nickname = nickname || "*"

    # Split the delta string
    delta = delta_string |> String.split(" ")

    # Disable these IRCv3 capabilities
    disabled =
      delta
      |> Enum.filter(&(String.first(&1) == "-"))
      |> Enum.map(&String.replace_prefix(&1, "-", ""))
      |> MapSet.new()

    # Enable these ones and join them with the old set of IRCv3 capabilities
    # when initially enabled
    enabled =
      delta
      |> Enum.filter(&(String.first(&1) != "-"))
      |> MapSet.new()
      |> MapSet.union(capabilities_old)
      |> MapSet.difference(disabled)

    # Adjusts the authentication finite state machine if legal
    cond do
      "sasl" in enabled and auth_state == :initialized ->
        socket
        |> ThousandIsland.Socket.send(
          Sencha.Message.encode(%Sencha.Message{
            prefix: Application.fetch_env!(:sencha, :host),
            command: "CAP",
            params: [nickname, "ACK"],
            trailing: delta
          })
        )

        # If SASL is enabled we can authenticate if and only if CAP END is sent
        {:noreply,
         {socket,
          %__MODULE__.UserState{
            state
            | capabilities: enabled,
              authentication_state: :waiting_for_authentication
          }}}

      "sasl" not in enabled and auth_state == :waiting_for_authentication ->
        # I think this corner case should be handled
        # CAP spec in IRCv3 allows for a "NAK" response

        socket
        |> ThousandIsland.Socket.send(
          Sencha.Message.encode(%Sencha.Message{
            prefix: Application.fetch_env!(:sencha, :host),
            command: "CAP",
            params: [nickname, "NAK"],
            trailing: delta
          })
        )

        {:noreply, {socket, state}}

      true ->
        socket
        |> ThousandIsland.Socket.send(
          Sencha.Message.encode(%Sencha.Message{
            prefix: Application.fetch_env!(:sencha, :host),
            command: "CAP",
            params: [nickname, "ACK"],
            trailing: delta
          })
        )

        # No need to adjust authentication finite state machine since SASL is
        # enabled
        {:noreply,
         {socket,
          %__MODULE__.UserState{
            state
            | capabilities: enabled
          }}}
    end
  end

  @impl GenServer
  def handle_cast(
        :capabilities_end,
        {socket,
         state = %__MODULE__.UserState{
           authentication_state: :waiting_for_capabilities,
           timeout_auth: timeout
         }}
      ) do
    # TODO: add welcome burst
    Process.cancel_timer(timeout)

    {:noreply,
     {socket, %__MODULE__.UserState{state | authentication_state: :ok, timeout_auth: nil}}}
  end

  @impl GenServer
  def handle_cast(
        {:authentication_put, auth_data_append},
        {socket,
         state = %__MODULE__.UserState{
           authentication_state: :waiting_for_authentication,
           authentication_data: auth_data
         }}
      ) do
    auth_result = __MODULE__.Authenticate.handle_packet(auth_data, auth_data_append)

    case auth_result do
      {:ok, decoded} ->
        decoded |> check_user_here({socket, state})

      {:continue, partial} ->
        {:noreply, {socket, %__MODULE__.UserState{state | authentication_data: partial}},
         socket.read_timeout}

      {:error, :too_long} ->
        socket
        |> ThousandIsland.Socket.send(
          Sencha.Message.encode(%Sencha.Message{
            prefix: Application.fetch_env!(:sencha, :host),
            command: "905",
            params: ["*"],
            trailing: "SASL message too long"
          })
        )

        {:noreply,
         {socket,
          %__MODULE__.UserState{
            state
            | authentication_data: []
          }}}

      {:error, :aborted} ->
        socket
        |> ThousandIsland.Socket.send(
          Sencha.Message.encode(%Sencha.Message{
            prefix: Application.fetch_env!(:sencha, :host),
            command: "906",
            params: ["*"],
            trailing: "SASL authentication aborted"
          })
        )

        {:noreply, {socket, %__MODULE__.UserState{state | authentication_data: []}},
         socket.read_timeout}
    end
  end

  # ===========================================================================
  # Connection is initialized
  # ===========================================================================
  @impl ThousandIsland.Handler
  def handle_connection(_socket, _state) do
    {:continue, __MODULE__.UserState.init(), :infinity}
  end

  # ===========================================================================
  # Connection packet handler
  # ===========================================================================
  @impl ThousandIsland.Handler
  def handle_data(data, _socket, state) do
    data
    |> Sencha.Message.decode()
    |> Stream.each(fn message -> send(self(), {:irc, message}) end)
    |> Stream.run()

    {:continue, state}
  end

  # ===========================================================================
  # Parsed commands are handled here
  # ===========================================================================
  @impl GenServer
  def handle_info({:irc, packet = %Sencha.Message{command: "CAP"}}, {socket, state}) do
    Sencha.Commands.Cap.handle_irc(self(), packet, {socket, state})

    {:noreply, {socket, state}}
  end

  @impl GenServer
  def handle_info({:irc, packet = %Sencha.Message{command: "AUTHENTICATE"}}, {socket, state}) do
    Sencha.Commands.Authenticate.handle_irc(self(), packet, {socket, state})

    {:noreply, {socket, state}}
  end

  @impl GenServer
  def handle_info(
        {:irc, %Sencha.Message{command: "ERROR", trailing: nil}},
        {socket, state}
      ) do
    socket |> perform_close("Client Quit")

    {:noreply, {socket, state}}
  end

  @impl GenServer
  def handle_info(
        {:irc, %Sencha.Message{command: "ERROR", trailing: err}},
        {socket, state}
      ) do
    socket |> perform_close(err)

    {:noreply, {socket, state}}
  end

  @impl GenServer
  def handle_info({:irc, _packet}, {socket, state}) do
    # Eat up all IRC commands that are invalid
    {:noreply, {socket, state}}
  end

  @impl GenServer
  def handle_info(:timeout_auth, {socket, state}) do
    socket
    |> perform_close("Authentication timed out")

    {:stop, :normal, {socket, state}}
  end

  # ===========================================================================
  # Connection drop callbacks
  # ===========================================================================
  @impl ThousandIsland.Handler
  def handle_shutdown(socket, _state) do
    # TODO: Send state to other clients
    socket
    |> perform_close("Server is going offline")

    :ok
  end

  @impl ThousandIsland.Handler
  def handle_error(:normal, _socket, _state), do: :ok

  @impl ThousandIsland.Handler
  def handle_error(_reason, socket, _state) do
    # TODO: Send state to other clients
    socket
    |> perform_close("Server closed connection")

    :ok
  end

  # ===========================================================================
  # Private callbacks
  # ===========================================================================
  defp perform_close(socket, reason) do
    socket
    |> ThousandIsland.Socket.send(
      Sencha.Message.encode(%Sencha.Message{
        command: "ERROR",
        trailing: "Closing Link: #{Application.fetch_env!(:sencha, :host)} (#{reason})"
      })
    )

    socket |> ThousandIsland.Socket.close()
  end

  defp check_user_here(decoded, {socket, state}) do
    case __MODULE__.Authenticate.check_user(decoded) do
      {:ok, user_data} ->
        {:ok, user_data}

      {:error, :no_such_user} ->
        socket
        |> ThousandIsland.Socket.send(
          Sencha.Message.encode(%Sencha.Message{
            prefix: Application.fetch_env!(:sencha, :host),
            command: "904",
            params: ["*"],
            trailing: "SASL authentication failed"
          })
        )

        :error

      {:error, :invalid_password} ->
        socket
        |> ThousandIsland.Socket.send(
          Sencha.Message.encode(%Sencha.Message{
            prefix: Application.fetch_env!(:sencha, :host),
            command: "904",
            params: ["*"],
            trailing: "SASL authentication failed"
          })
        )

        :error

      {:error, :malformed} ->
        socket
        |> ThousandIsland.Socket.send(
          Sencha.Message.encode(%Sencha.Message{
            prefix: Application.fetch_env!(:sencha, :host),
            command: "904",
            params: ["*"],
            trailing: "SASL authentication failed"
          })
        )

        :error
    end
    |> check_locked_here({socket, state})
  end

  defp check_locked_here({:ok, user}, {socket, state = %__MODULE__.UserState{}}) do
    case __MODULE__.Authenticate.check_locked(user) do
      {:ok, %Sencha.Repo.User{nickname: nickname}} ->
        socket
        |> ThousandIsland.Socket.send(
          Sencha.Message.encode(%Sencha.Message{
            prefix: Application.fetch_env!(:sencha, :host),
            command: "900",
            params: [nickname, nickname |> __MODULE__.UserState.hostmask(), nickname],
            trailing: "You are now logged in as " <> nickname
          })
        )

        socket
        |> ThousandIsland.Socket.send(
          Sencha.Message.encode(%Sencha.Message{
            prefix: Application.fetch_env!(:sencha, :host),
            command: "903",
            params: [nickname],
            trailing: "SASL authentication successful"
          })
        )

        {:noreply,
         {socket,
          %__MODULE__.UserState{
            state
            | authentication_data: [],
              authentication_state: :waiting_for_capabilities,
              nickname: nickname
          }}}

      {:error, {:locked, %Sencha.Repo.User{nickname: nickname, locked_reason: reason}}} ->
        socket
        |> ThousandIsland.Socket.send(
          Sencha.Message.encode(%Sencha.Message{
            prefix: Application.fetch_env!(:sencha, :host),
            command: "902",
            params: [nickname],
            trailing: "Your account is locked: " <> reason
          })
        )

        {:noreply,
         {socket,
          %__MODULE__.UserState{
            state
            | authentication_data: []
          }}}
    end
  end

  defp check_locked_here(:error, {socket, state = %__MODULE__.UserState{}}) do
    {:noreply,
     {socket,
      %__MODULE__.UserState{
        state
        | authentication_data: []
      }}}
  end
end
