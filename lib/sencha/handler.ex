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

  @doc """
  Sends an encoded IRC message to this user.
  """
  def send_message(pid, message), do: GenServer.cast(pid, {:send_message, message})
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
  def handle_cast({:send_message, message}, {socket, state}) do
    socket
    |> ThousandIsland.Socket.send(message |> Sencha.Message.encode())

    {:noreply, {socket, state}}
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
           timeout_auth: timeout,
           rdns_host: rdns_host,
           nickname: nickname
         }}
      ) do
    state = %__MODULE__.UserState{state | authentication_state: :ok}

    Process.cancel_timer(timeout)

    child =
      Sencha.User.Supervisor.start_child(%{
        handler_process: self(),
        rdns_host: rdns_host,
        nickname: nickname
      })

    case child do
      {:ok, pid} ->
        Process.link(pid)

        {:noreply, {socket, %__MODULE__.UserState{state | user_process: pid}}}

      {:error, {:already_started, _pid}} ->
        socket
        |> perform_close("Account already in use")

        {:noreply, {socket, state}}

      {:error, :max_children} ->
        socket
        |> perform_close("Too many connections on this server")

        {:noreply, {socket, state}}
    end
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
        {:noreply, {socket, %__MODULE__.UserState{state | authentication_data: partial}}}

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

        {:noreply, {socket, %__MODULE__.UserState{state | authentication_data: []}}}
    end
  end

  # ===========================================================================
  # Connection is initialized
  # ===========================================================================
  @impl ThousandIsland.Handler
  def handle_connection(socket, _state) do
    {:ok, {peer, _port}} = ThousandIsland.Socket.peername(socket)

    socket
    |> ThousandIsland.Socket.send(
      Sencha.Message.encode(%Sencha.Message{
        prefix: Application.fetch_env!(:sencha, :host),
        command: "NOTICE",
        params: ["*"],
        trailing: "Getting your hostname"
      })
    )

    task = Task.async(fn -> __MODULE__.LookupRDNS.lookup(peer) end)

    host =
      case Task.await(task) do
        {_, result} when result != :error ->
          result

        _ ->
          socket
          |> ThousandIsland.Socket.send(
            Sencha.Message.encode(%Sencha.Message{
              prefix: Application.fetch_env!(:sencha, :host),
              command: "NOTICE",
              params: ["*"],
              trailing: "Could not get your hostname, using your IP address instead"
            })
          )

          :inet.ntoa(peer) |> to_string
      end

    socket
    |> ThousandIsland.Socket.send(
      Sencha.Message.encode(%Sencha.Message{
        prefix: Application.fetch_env!(:sencha, :host),
        command: "NOTICE",
        params: ["*"],
        trailing: "Your probed hostname or IP address is #{host}"
      })
    )

    kline =
      :persistent_term.get(Sencha.KLines, [])
      |> Enum.filter(fn kline ->
        case kline do
          {:cidr, cidr, _reason} -> InetCidr.contains?(cidr, peer)
          {:host, host_regex, _reason} -> Regex.match?(host_regex, host)
        end
      end)

    case kline do
      [] ->
        :ok

      kline ->
        # first k-line takes precedence because that is Elixir's happy path
        {_, reason} = hd(kline)
        socket |> perform_close("K-Lined (#{reason})")

        :ok
    end

    {:continue, %__MODULE__.UserState{__MODULE__.UserState.init() | rdns_host: host}, :infinity}
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
        {:irc, packet = %Sencha.Message{command: "PING"}},
        {socket, state}
      ) do
    Sencha.Commands.Ping.handle_irc(self(), packet, {socket, state})

    {:noreply, {socket, state}}
  end

  @impl GenServer
  def handle_info(
        {:irc, packet = %Sencha.Message{command: "PONG"}},
        {socket, state}
      ) do
    Sencha.Commands.Pong.handle_irc(self(), packet, {socket, state})

    {:noreply, {socket, state}}
  end

  @impl GenServer
  def handle_info({:irc, packet = %Sencha.Message{command: "MOTD"}}, {socket, state}) do
    Sencha.Commands.Motd.handle_irc(self(), packet, {socket, state})

    {:noreply, {socket, state}}
  end

  @impl GenServer
  def handle_info({:irc, packet = %Sencha.Message{command: "OPER"}}, {socket, state}) do
    Sencha.Commands.Oper.handle_irc(self(), packet, {socket, state})

    {:noreply, {socket, state}}
  end

  @impl GenServer
  def handle_info({:irc, packet = %Sencha.Message{command: "REHASH"}}, {socket, state}) do
    Sencha.Commands.Rehash.handle_irc(self(), packet, {socket, state})

    {:noreply, {socket, state}}
  end

  @impl GenServer
  def handle_info({:irc, packet = %Sencha.Message{command: "SQUIT"}}, {socket, state}) do
    Sencha.Commands.Squit.handle_irc(self(), packet, {socket, state})

    {:noreply, {socket, state}}
  end

  @impl GenServer
  def handle_info({:irc, packet = %Sencha.Message{command: "MODE"}}, {socket, state}) do
    Sencha.Commands.Mode.handle_irc(self(), packet, {socket, state})

    {:noreply, {socket, state}}
  end

  @impl GenServer
  def handle_info({:irc, packet = %Sencha.Message{command: "JOIN"}}, {socket, state}) do
    Sencha.Commands.Join.handle_irc(self(), packet, {socket, state})

    {:noreply, {socket, state}}
  end

  @impl GenServer
  def handle_info({:irc, packet = %Sencha.Message{command: "PART"}}, {socket, state}) do
    Sencha.Commands.Part.handle_irc(self(), packet, {socket, state})

    {:noreply, {socket, state}}
  end

  @impl GenServer
  def handle_info({:irc, packet = %Sencha.Message{command: "QUIT"}}, {socket, state}) do
    Sencha.Commands.Quit.handle_irc(self(), packet, {socket, state})

    {:noreply, {socket, state}}
  end

  @impl GenServer
  def handle_info({:irc, packet = %Sencha.Message{command: "PRIVMSG"}}, {socket, state}) do
    Sencha.Commands.Privmsg.handle_irc(self(), packet, {socket, state})

    {:noreply, {socket, state}}
  end

  @impl GenServer
  def handle_info({:irc, packet = %Sencha.Message{command: "NOTICE"}}, {socket, state}) do
    Sencha.Commands.Notice.handle_irc(self(), packet, {socket, state})

    {:noreply, {socket, state}}
  end

  @impl GenServer
  def handle_info({:irc, packet = %Sencha.Message{command: "NAMES"}}, {socket, state}) do
    Sencha.Commands.Names.handle_irc(self(), packet, {socket, state})

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
    |> perform_close("Authentication timeout")

    {:stop, :normal, {socket, state}}
  end

  @impl GenServer
  def handle_info({:EXIT, _what, :normal}, {socket, state}) do
    {:noreply, {socket, state}}
  end

  @impl GenServer
  def handle_info({:EXIT, _what, _reason}, {socket, state}) do
    socket
    |> perform_close("Server closed connection")

    {:noreply, {socket, state}}
  end

  # ===========================================================================
  # Connection drop callbacks
  # ===========================================================================
  @impl ThousandIsland.Handler
  def handle_shutdown(socket, _state) do
    socket
    |> perform_close("Server is going offline")

    :ok
  end

  @impl ThousandIsland.Handler
  def handle_error(:normal, _socket, _state), do: :ok

  @impl ThousandIsland.Handler
  def handle_error(_reason, socket, _state) do
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
        prefix: Application.fetch_env!(:sencha, :host),
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

  defp check_locked_here(
         {:ok, user},
         {socket,
          state = %__MODULE__.UserState{
            rdns_host: rdns_host
          }}
       ) do
    case __MODULE__.Authenticate.check_locked(user) do
      {:ok, %Sencha.Repo.User{nickname: nickname}} ->
        state = %__MODULE__.UserState{
          state
          | authentication_data: [],
            authentication_state: :waiting_for_capabilities,
            nickname: nickname
        }

        socket
        |> ThousandIsland.Socket.send(
          Sencha.Message.encode(%Sencha.Message{
            prefix: Application.fetch_env!(:sencha, :host),
            command: "900",
            params: [nickname, "#{nickname}!~Sencha@#{rdns_host}", nickname],
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

        {:noreply, {socket, state}}

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
