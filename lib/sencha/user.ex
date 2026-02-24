defmodule Sencha.User do
  use GenServer, restart: :temporary

  # ===========================================================================
  # Public callbacks
  # ===========================================================================
  @doc """
  Start a user process. This occurs after successful authentication.
  """
  def start_link(args = %{nickname: nickname}) do
    GenServer.start_link(__MODULE__, args, name: {:global, nickname})
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
  Sends a WALLOPS to this user.
  """
  def wallops(pid, message) do
    GenServer.cast(pid, {:wallops, message})
  end

  # ===========================================================================
  # Behavioral callbacks (initialization)
  # ===========================================================================
  @impl GenServer
  def init(%{handler_process: handler_process, rdns_host: rdns_host, nickname: nickname}) do
    # Elixir does really weird stuff related to Dynamic Supervisors and
    # counting how many children one has.
    #
    # Therefore, we must delay the welcome burst.
    Process.send_after(self(), :timeout_welcome_burst, 100)

    {:ok,
     %__MODULE__.State{
       nickname: nickname,
       handler_process: handler_process,
       rdns_host: rdns_host,
       timeout_ping: do_timeout_ping(),
       last_ping_from_server: DateTime.utc_now(:second),
       modes: __MODULE__.Modes.defaults()
     }}
  end

  # ===========================================================================
  # Behavioral callbacks (calling messages)
  # ===========================================================================
  @impl GenServer
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
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
        :grant_operator,
        state = %__MODULE__.State{nickname: nickname, modes: modes, handler_process: handler}
      ) do
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

  @impl GenServer
  def handle_cast(
        :send_motd,
        state
      ) do
    __MODULE__.MOTD.send_to_client(state)
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

  # ===========================================================================
  # Behavioral callbacks (timer messages)
  # ===========================================================================
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
    set_modes(self(), MapSet.delete(modes, ?o))

    {:noreply, state}
  end

  @impl GenServer
  def handle_info(
        :timeout_ping_hard,
        state = %__MODULE__.State{handler_process: handler, last_ping_from_server: t0}
      ) do
    t1 = DateTime.utc_now(:second)

    Sencha.Handler.disconnect(handler, "Ping timeout (#{DateTime.diff(t1, t0)} seconds)")

    {:stop, :normal, state}
  end

  @impl GenServer
  def handle_info(
        :timeout_welcome_burst,
        state = %__MODULE__.State{handler_process: handler, nickname: nickname, modes: modes}
      ) do
    host = Application.fetch_env!(:sencha, :host)
    version = "sencha-" <> to_string(Application.spec(:sencha)[:vsn])

    [
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
      %Sencha.Message{
        prefix: host,
        command: "005",
        params: [
          nickname,
          "CHANNELLEN=#{Sencha.Repo.Channel.max_name_length() + 1}",
          "CHANTYPES=#",
          "EXTBAN=~,is",
          "MAXNICKLEN=#{Sencha.Repo.User.max_nickname_length()}"
        ],
        trailing: "are supported by this server"
      }
    ]
    |> Enum.map(fn message -> Sencha.Handler.send_message(handler, message) end)

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
