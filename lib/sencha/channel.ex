defmodule Sencha.Channel do
  @moduledoc """
  IRC channel server
  """
  use GenServer

  # ===========================================================================
  # Public calls
  # ===========================================================================
  def start_link(_init_arg, aggregate: aggregate) do
    where = {:via, Registry, {Sencha.ChannelRegistry, aggregate}}

    GenServer.start_link(__MODULE__, [aggregate: aggregate], name: where)
  end

  @doc """
  Makes the specified username join
  """
  def join(pid, user, socket_pid), do: GenServer.cast(pid, {:join, user, socket_pid})

  @doc """
  Makes the specified username part
  """
  def part(pid, user, socket_pid, reason \\ nil),
    do: GenServer.cast(pid, {:part, user, socket_pid, reason})

  @doc """
  Makes the specified username talk
  """
  def talk(pid, user, socket_pid, message),
    do: GenServer.cast(pid, {:talk, user, socket_pid, message})

  @doc """
  Makes the specified username quit
  """
  def quit(pid, user), do: GenServer.cast(pid, {:quit, user})

  @doc """
  Gets all usernames in the channel
  """
  def get_users(pid), do: GenServer.call(pid, :get_users)

  @doc """
  Gets the channel's name
  """
  def get_name(pid), do: GenServer.call(pid, :get_name)

  # ===========================================================================
  # Behavioral callbacks
  # ===========================================================================
  @impl true
  def init(aggregate: aggregate) do
    case aggregate |> lookup_via_gateway do
      {:ok, info} ->
        {:ok,
         %{
           channel: "#" <> (info.aggregate |> String.downcase()),
           topic: info.description,
           users_sockets: %{},
           created: info.inserted_at |> DateTime.to_unix()
         }}

      {:error, what} ->
        {:stop, {:error, what}}
    end
  end

  @impl true
  def handle_call(:get_users, _from, state = %{users_sockets: users_sockets}) do
    {:reply, {:ok, users_sockets}, state}
  end

  @impl true
  def handle_cast(
        {:join, user, socket_pid},
        state = %{users_sockets: users_sockets, channel: channel_name}
      )
      when is_map_key(user, users_sockets) do
    Sencha.Handler.on_already_present(socket_pid, channel_name)
    {:noreply, state}
  end

  @impl true
  def handle_cast(
        {:part, user, socket_pid, _reason},
        state = %{users_sockets: users_sockets, channel: channel_name}
      )
      when not is_map_key(user, users_sockets) do
    Sencha.Handler.on_not_present(socket_pid, channel_name)
    {:noreply, state}
  end

  @impl true
  def handle_cast(
        {:talk, user, socket_pid, _message},
        state = %{users_sockets: users_sockets, channel: channel_name}
      )
      when not is_map_key(user, users_sockets) do
    Sencha.Handler.on_not_present(socket_pid, channel_name)
    {:noreply, state}
  end

  @impl true
  def handle_cast(
        {:join, user, socket_pid},
        state = %{
          users_sockets: users_sockets,
          channel: channel_name,
          topic: topic,
          created: created
        }
      ) do
    everyone = users_sockets |> Map.keys()
    everyone = [user | everyone]
    everyone = ["@Services" | everyone]

    # Handle my own cast
    Sencha.Handler.on_join(socket_pid, channel_name, everyone, {topic, created})
    {:ok, hostmask} = Sencha.Handler.get_hostmask(socket_pid)

    # Handle everyone else's cast
    for {_other_user, other_socket_pid} <- users_sockets do
      Sencha.Handler.on_join(other_socket_pid, channel_name, hostmask)
    end

    {:noreply, state |> put_in([:users_sockets, user], socket_pid)}
  end

  @impl true
  def handle_cast(
        {:part, user, socket_pid, reason},
        state = %{users_sockets: users_sockets, channel: channel_name}
      ) do
    {:ok, hostmask} = Sencha.Handler.get_hostmask(socket_pid)

    for {_other_user, other_socket_pid} <- users_sockets do
      Sencha.Handler.on_part(other_socket_pid, channel_name, hostmask, reason)
    end

    {:noreply, state |> pop_in([:users_sockets, user])}
  end

  @impl true
  def handle_cast(
        {:talk, _user, socket_pid, message},
        state = %{users_sockets: users_sockets, channel: channel_name}
      ) do
    {:ok, hostmask} = Sencha.Handler.get_hostmask(socket_pid)

    for {_other_user, other_socket_pid} <- users_sockets do
      Sencha.Handler.on_privmsg(other_socket_pid, channel_name, hostmask, message)
    end

    {:noreply, state}
  end

  @impl true
  def handle_cast(
        {:quit, user},
        state
      ) do
    # We already sent our quit messages from the User Pool
    {:noreply, state |> pop_in([:users_sockets, user])}
  end

  # ===========================================================================
  # Private calls
  # ===========================================================================
  defp lookup_via_gateway(aggregate) do
    # Look for nearest gateway
    fastest_node = Sencha.Gateway.fastest_node()

    # Try to get info from the nearest gateway
    if is_nil(fastest_node) do
      {:error, :no_gateway}
    else
      Sencha.Gateway.aggregate_info(
        fastest_node,
        self(),
        aggregate |> String.replace_prefix("#", "")
      )

      receive do
        {Exsemantica.Gateway, ^fastest_node, {:aggregate_info, {:ok, info}}} ->
          {:ok, info}

        {Exsemantica.Gatewat, ^fastest_node, {:aggregate_info, {:error, what}}} ->
          {:error, what}
      after
        5000 ->
          {:error, :gateway_timeout}
      end
    end
  end
end
