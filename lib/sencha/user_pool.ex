defmodule Sencha.UserPool do
  @moduledoc """
  Stores all users for easy iteration.

  Also has the duty of pinging users.
  """
  # Ping interval in milliseconds
  @ping_interval 10_000

  # Ping timeout in milliseconds
  @ping_timeout @ping_interval + 5_000

  @user_pool_terminated "Server error (user pool terminated)"

  use GenServer
  require Logger

  defmodule Entry do
    defstruct ping_timer: nil,
              timeout_timer: nil,
              socket_pid: nil,
              last_ping: DateTime.utc_now(:second),
              channels: MapSet.new()
  end

  @doc """
  Starts the user pool.
  """
  def start_link([]) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Logs a username into the pool.
  """
  def log_in(user) do
    GenServer.call(__MODULE__, {:log_in, user})
  end

  @doc """
  Gets this user's channels.
  """
  def get_channels(user) do
    GenServer.call(__MODULE__, {:get_channels, user})
  end

  @doc """
  Gets this user's socket PID.
  """
  def get_socket(user) do
    GenServer.call(__MODULE__, {:get_socket, user})
  end

  @doc """
  Logs a username out of the pool.
  """
  def log_out(user, reason) do
    GenServer.cast(__MODULE__, {:log_out, user, reason})
  end

  @doc """
  Returns the pool usernames.
  """
  def all() do
    GenServer.call(__MODULE__, :all)
  end

  # ===========================================================================
  # Behavioral callbacks
  # ===========================================================================
  @impl true
  def init([]) do
    {:ok, %{}}
  end

  @impl true
  def handle_call({:log_in, user}, _from, state) when is_map_key(state, user) do
    {:reply, {:error, :already_started}, state}
  end

  @impl true
  def handle_call({:log_in, user}, from, state) do
    Logger.debug("#{user} connects")

    {:reply, :ok,
     state
     |> put_in([user], %Entry{
       ping_timer: Process.send_after(from, {:ping, self()}, @ping_interval),
       timeout_timer: Process.send_after(self(), {:timeout, user}, @ping_timeout),
       socket_pid: from
     })}
  end

  @impl true
  def handle_call({:get_channels, user}, _from, state) when is_map_key(state, user) do
    {:reply, {:ok, state |> get_in([user, :channels])}, state}
  end

  @impl true
  def handle_call({:get_channels, user}, _from, state) do
    {:reply, {:error, :not_found}, state}
  end

  @impl true
  def handle_call({:get_socket, user}, _from, state) when is_map_key(state, user) do
    {:reply, {:ok, state |> get_in([user, :socket_pid])}, state}
  end

  @impl true
  def handle_call({:get_socket, user}, _from, state) do
    {:reply, {:error, :not_found}, state}
  end

  @impl true
  def handle_cast({:log_out, user, reason}, state) when is_map_key(state, user) do
    Logger.debug("#{user} disconnects (#{reason})")
    entry = state |> get_in([user])

    socket = entry.socket_pid
    {:ok, hostmask} = Sencha.Handler.get_hostmask(socket)

    quit(entry, hostmask, reason)
    Sencha.Handler.on_disconnect(socket, reason)

    {:noreply, state |> pop_in([user])}
  end

  @impl true
  def handle_cast({:log_out, _user, _reason}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info({:timeout, user}, state) when is_map_key(state, user) do
    last_ping = state |> get_in([user, :last_ping])

    log_out(
      user,
      "Ping timeout: (#{DateTime.utc_now(:second) |> DateTime.diff(last_ping, :second)} seconds)"
    )

    {:noreply, state}
  end

  @impl true
  def handle_info({:timeout, _user}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info({:pong, from, user}, state) when is_map_key(state, user) do
    # Cancel pending ping and timeout disconnects
    Process.cancel_timer(state |> get_in([user, :timeout_timer]))
    Process.cancel_timer(state |> get_in([user, :ping_timer]))

    {:noreply,
     state
     |> update_in([user], fn data ->
       %Entry{
         data
         | ping_timer: Process.send_after(from, {:ping, self()}, @ping_interval),
           timeout_timer: Process.send_after(self(), {:timeout, user}, @ping_timeout),
           last_ping: DateTime.utc_now(:second)
       }
     end)}
  end

  @impl true
  def terminate(_reason, state) do
    for {username, entry} <- state do
      log_out(username, @user_pool_terminated)
    end

    :ok
  end

  # ===========================================================================
  # Private functions
  # ===========================================================================
  defp quit(%Entry{channels: channels}, hostmask, reason) do
    socket_pids =
      channels
      |> Enum.reduce(%{}, fn channel_pid, accumulator ->
        Sencha.Channel.get_users(channel_pid)
        |> Map.merge(accumulator)
      end)
      |> Map.values()

    for socket_pid <- socket_pids do
      Sencha.Handler.on_quit(socket_pid, hostmask, reason)
    end

    :ok
  end
end
