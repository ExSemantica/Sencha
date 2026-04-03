defmodule Sencha.User do
  @moduledoc """
  Handles user-level logic after `Sencha.Handler` hands off its SASL duties.
  """
  use GenServer, restart: :temporary

  # ===========================================================================
  # Public callbacks
  # ===========================================================================
  @doc """
  Start a user process. This occurs after successful authentication.
  """
  def start_link(args = %{nickname: nickname}) do
    GenServer.start_link(__MODULE__, args, name: {:global, {__MODULE__, nickname}})
  end

  @doc """
  Resets the PING timers.
  """
  def receive_ping(pid) do
    GenServer.cast(pid, :receive_ping)
  end

  @doc """
  Forcefully sets user MODEs.
  """
  def set_modes(pid, modes) do
    GenServer.cast(pid, {:set_modes, modes})
  end

  @doc """
  Gets this user's state.
  """
  def get_state(pid) do
    GenServer.call(pid, :get_state)
  end

  @doc """
  Grants a user IRC operator privileges temporarily.
  """
  def grant_operator(pid) do
    GenServer.cast(pid, :grant_operator)
  end

  @doc """
  Sends the MOTD to this user.
  """
  def send_motd(pid) do
    GenServer.cast(pid, :send_motd)
  end

  @doc """
  Sends LUSERS to this user.
  """
  def send_lusers(pid) do
    GenServer.cast(pid, :send_lusers)
  end

  @doc """
  Sends a WALLOPS to this user.
  """
  def wallops(pid, message) do
    GenServer.cast(pid, {:wallops, message})
  end

  @doc """
  Recommended endpoint for a user to 'JOIN' a `Sencha.Channel`
  """
  def join(pid, channel_name) do
    GenServer.cast(pid, {:join, channel_name})
  end

  @doc """
  Recommended endpoint for a user to 'PART' a `Sencha.Channel`
  """
  def part(pid, channel_name, reason) do
    GenServer.cast(pid, {:part, channel_name, reason})
  end

  @doc """
  Recommended endpoint for a user to send a disconnect reason
  """
  def disconnect(pid, reason) do
    GenServer.cast(pid, {:disconnect, reason})
  end

  @doc """
  Recommended endpoint for a user to receive another user's disconnect reason
  """
  def other_quit(pid, host, reason) do
    GenServer.cast(pid, {:other_quit, host, reason})
  end

  @doc """
  Recommended endpoint to receive a private message from another user.
  """
  def privmsg(pid, host, message) do
    GenServer.cast(pid, {:privmsg, host, message})
  end

  @doc """
  Recommended endpoint to receive a notice from another user.
  """
  def notice(pid, host, message) do
    GenServer.cast(pid, {:notice, host, message})
  end

  # ===========================================================================
  # Behavioral callbacks (initialization/termination)
  # ===========================================================================
  @impl GenServer
  def init(%{handler_process: handler_process, rdns_host: rdns_host, nickname: nickname}) do
    Sencha.Scoreboard.change_total(1)

    # Elixir does really weird stuff related to `Supervisor` processes and
    # counting how many children one has.
    #
    # Therefore, we must delay the welcome burst.
    Process.send_after(self(), :timeout_welcome_burst, 100)

    # Trap exits from the handler process
    Process.flag(:trap_exit, true)

    {:ok,
     %__MODULE__.State{
       nickname: nickname,
       handler_process: handler_process,
       rdns_host: rdns_host,
       timeout_ping: do_timeout_ping(),
       last_ping_from_server: DateTime.utc_now(:second),
       modes: __MODULE__.Modes.defaults(),
       channel_names: MapSet.new()
     }}
  end

  # ===========================================================================
  # Behavioral callbacks (calling messages)
  # ===========================================================================
  @impl GenServer
  def handle_call(:get_state, _from, state) do
    {:reply, {:ok, state}, state}
  end

  # ===========================================================================
  # Behavioral callbacks (casting messages)
  # ===========================================================================
  @impl GenServer
  def handle_cast(
        :receive_ping,
        state = %__MODULE__.State{
          timeout_ping: soft,
          timeout_ping_hard: hard
        }
      ) do
    Process.cancel_timer(soft)
    Process.cancel_timer(hard)

    {:noreply,
     %__MODULE__.State{
       state
       | last_ping_from_server: DateTime.utc_now(:second),
         timeout_ping: do_timeout_ping()
     }}
  end

  @impl GenServer
  def handle_cast(
        {:set_modes, new},
        state = %__MODULE__.State{}
      ) do
    state = %__MODULE__.State{state | modes: new}
    __MODULE__.Modes.send_to_client(state)

    {:noreply, state}
  end

  @impl GenServer
  def handle_cast(
        {:disconnect, reason},
        state = %__MODULE__.State{handler_process: handler, channel_names: channels}
      ) do
    Sencha.Scoreboard.change_total(-1)

    hostmask = __MODULE__.State.hostmask(state)

    {_channels, all_users} =
      channels
      |> Enum.map_reduce(MapSet.new(), fn channel, acc ->
        channel_pid = GenServer.whereis({:global, {Sencha.Channel, channel}})

        if is_nil(channel_pid) do
          {channel, acc}
        else
          channel_pid |> Sencha.Channel.user_remove(self())
          {:ok, users_set} = Sencha.Channel.users_accumulate(channel_pid)
          {channel, MapSet.union(acc, users_set)}
        end
      end)

    for user_pid <- all_users do
      Sencha.User.other_quit(user_pid, hostmask, reason)
    end

    Sencha.Handler.send_message(handler, %Sencha.Message{
      prefix: Application.fetch_env!(:sencha, :host),
      command: "ERROR",
      trailing: "Closing Link: #{Application.fetch_env!(:sencha, :host)} (#{reason})"
    })

    {:stop, :normal, state}
  end

  @impl GenServer
  def handle_cast(
        {:other_quit, host, reason},
        state = %__MODULE__.State{handler_process: handler}
      ) do
    Sencha.Handler.send_message(handler, %Sencha.Message{
      prefix: host,
      command: "QUIT",
      trailing: reason
    })

    {:noreply, state}
  end

  @impl GenServer
  def handle_cast(
        :grant_operator,
        state = %__MODULE__.State{nickname: nickname, modes: modes, handler_process: handler}
      ) do
    if MapSet.member?(modes, ?o) do
      # User is already an oper. Do nothing.
      {:noreply, state}
    else
      Sencha.Scoreboard.change_operators(1)
      time = DateTime.utc_now() |> DateTime.add(Application.fetch_env!(:sencha, :oper_duration))

      Sencha.Handler.send_message(handler, %Sencha.Message{
        prefix: Application.fetch_env!(:sencha, :host),
        command: "381",
        params: [nickname],
        trailing: "Operator temporarily granted until #{time |> DateTime.to_string()}"
      })

      set_modes(self(), MapSet.put(modes, ?o))

      {:noreply, %__MODULE__.State{state | timeout_operator: do_timeout_operator()}}
    end
  end

  @impl GenServer
  def handle_cast(
        :send_motd,
        state
      ) do
    __MODULE__.MOTD.send_to_client(state)
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast(:send_lusers, state) do
    __MODULE__.Lusers.send_to_client(state)
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast(
        {:wallops, message},
        state = %__MODULE__.State{handler_process: handler, modes: modes}
      ) do
    if MapSet.member?(modes, ?w) do
      Sencha.Handler.send_message(handler, %Sencha.Message{
        prefix: Application.fetch_env!(:sencha, :host),
        command: "WALLOPS",
        trailing: message
      })
    end

    {:noreply, state}
  end

  @impl GenServer
  def handle_cast(
        {:join, channel_name},
        state = %__MODULE__.State{
          handler_process: handler,
          nickname: nickname,
          channel_names: channels
        }
      ) do
    case Sencha.Channel.Supervisor.start_child(%{name: channel_name, joiner: nickname}) do
      {:ok, pid} ->
        Sencha.Channel.user_join(pid, self())

        {:noreply, %__MODULE__.State{state | channel_names: MapSet.put(channels, channel_name)}}

      {:error, {:already_started, pid}} ->
        Sencha.Channel.user_join(pid, self())

        {:noreply, %__MODULE__.State{state | channel_names: MapSet.put(channels, channel_name)}}

      {:error, {:locked, name, reason}} ->
        Sencha.Handler.send_message(handler, %Sencha.Message{
          prefix: Application.fetch_env!(:sencha, :host),
          command: "476",
          params: [nickname, name],
          trailing: "This channel is locked: " <> reason
        })

        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_cast(
        {:part, channel_name, reason},
        state = %__MODULE__.State{
          channel_names: channels
        }
      ) do
    Sencha.Channel.user_part({:global, {Sencha.Channel, channel_name}}, self(), reason)
    {:noreply, %__MODULE__.State{state | channel_names: MapSet.delete(channels, channel_name)}}
  end

  @impl GenServer
  def handle_cast(
        {:privmsg, hostmask, message},
        state = %__MODULE__.State{nickname: nick, handler_process: handler}
      ) do
    Sencha.Handler.send_message(handler, %Sencha.Message{
      prefix: hostmask,
      command: "PRIVMSG",
      params: [nick],
      trailing: message
    })

    {:noreply, state}
  end

  @impl GenServer
  def handle_cast(
        {:notice, hostmask, message},
        state = %__MODULE__.State{nickname: nick, handler_process: handler}
      ) do
    Sencha.Handler.send_message(handler, %Sencha.Message{
      prefix: hostmask,
      command: "NOTICE",
      params: [nick],
      trailing: message
    })

    {:noreply, state}
  end

  # ===========================================================================
  # Behavioral callbacks (info messages)
  # ===========================================================================
  @impl GenServer
  def handle_info({:EXIT, _pid, {:shutdown, :peer_closed}}, state) do
    disconnect(self(), "Read error: Connection reset by peer")

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:EXIT, _pid, _reason}, state) do
    disconnect(self(), "Server closed connection")

    {:noreply, state}
  end

  @impl GenServer
  def handle_info(:timeout_ping, state = %__MODULE__.State{handler_process: handler}) do
    Sencha.Handler.send_message(handler, %Sencha.Message{
      prefix: Application.fetch_env!(:sencha, :host),
      command: "PING",
      trailing: Application.fetch_env!(:sencha, :host)
    })

    {:noreply,
     %__MODULE__.State{
       state
       | timeout_ping_hard: do_timeout_ping_hard()
     }}
  end

  @impl GenServer
  def handle_info(
        :timeout_operator,
        state = %__MODULE__.State{modes: modes}
      ) do
    Sencha.Scoreboard.change_operators(-1)
    set_modes(self(), MapSet.delete(modes, ?o))

    {:noreply, state}
  end

  @impl GenServer
  def handle_info(
        :timeout_ping_hard,
        state = %__MODULE__.State{last_ping_from_server: t0}
      ) do
    t1 = DateTime.utc_now(:second)

    disconnect(self(), "Ping timeout (#{DateTime.diff(t1, t0)} seconds)")

    {:noreply, state}
  end

  @impl GenServer
  def handle_info(
        :timeout_welcome_burst,
        state = %__MODULE__.State{handler_process: handler, nickname: nickname, modes: modes}
      ) do
    host = Application.fetch_env!(:sencha, :host)
    version = "sencha-" <> to_string(Application.spec(:sencha)[:vsn])

    burst = [
      %Sencha.Message{
        prefix: host,
        command: "001",
        params: [nickname],
        trailing: "Welcome to Sencha, #{nickname}"
      },
      %Sencha.Message{
        prefix: host,
        command: "002",
        params: [nickname],
        trailing: "Your host is #{host}, running version #{version}"
      },
      %Sencha.Message{
        prefix: host,
        command: "003",
        params: [nickname],
        trailing:
          "This server was started #{:persistent_term.get(Sencha.Application.Started) |> DateTime.to_string()}"
      },
      %Sencha.Message{
        prefix: host,
        command: "004",
        params: [
          nickname,
          host,
          version,
          __MODULE__.Modes.format_supported(),
          Sencha.Channel.Modes.format_supported(),
          Sencha.Channel.Modes.format_supported_parameters()
        ]
      },
      # TODO: Make more mask types
      # For reference: ~c -> CIDR, ~h -> hostmask, ~u -> username
      # We only support username bans for now, but we'll support others later
      %Sencha.Message{
        prefix: host,
        command: "005",
        params: [
          nickname,
          "CHANNELLEN=#{Sencha.Repo.Channel.max_name_length() + 1}",
          "CHANTYPES=#",
          "EXTBAN=~,u",
          "MAXNICKLEN=#{Sencha.Repo.User.max_nickname_length()}",
          # TODO: fix these so it will support multiple targets
          "TARGMAX=JOIN:#{Sencha.Commands.Join.max_targets()},NAMES:#{Sencha.Commands.Names.max_targets()},PART:#{Sencha.Commands.Part.max_targets()},PRIVMSG:#{Sencha.Commands.Privmsg.max_targets()}"
        ],
        trailing: "are supported by this server"
      }
    ]

    for b <- burst do
      Sencha.Handler.send_message(handler, b)
    end

    __MODULE__.Lusers.send_to_client(state)
    __MODULE__.MOTD.send_to_client(state)

    if MapSet.size(modes) > 0 do
      __MODULE__.Modes.send_to_client(state)
    end

    {:noreply, state}
  end

  # ===========================================================================
  # Private callbacks
  # ===========================================================================
  defp do_timeout_ping do
    Process.send_after(
      self(),
      :timeout_ping,
      Application.fetch_env!(:sencha, :ping_timeout)
    )
  end

  defp do_timeout_ping_hard do
    Process.send_after(
      self(),
      :timeout_ping_hard,
      Application.fetch_env!(:sencha, :ping_timeout_hard)
    )
  end

  defp do_timeout_operator do
    Process.send_after(
      self(),
      :timeout_operator,
      Application.fetch_env!(:sencha, :oper_duration) * 1_000
    )
  end
end
