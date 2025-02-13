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

  def join(pid, user), do: GenServer.cast(pid, {:join, user})
  def part(pid, user, reason \\ nil), do: GenServer.cast(pid, {:part, user, reason})
  def talk(pid, user, message), do: GenServer.cast(pid, {:talk, user, message})
  def quit(pid, user), do: GenServer.cast(pid, {:quit, user})
  def get_users(pid), do: GenServer.call(pid, :get_users)
  def get_name(pid), do: GenServer.call(pid, :get_name)

  # ===========================================================================
  # GenServer callbacks
  # ===========================================================================
  @impl true
  def init(aggregate: aggregate) do
    case aggregate |> lookup_via_gateway do
      {:ok, info} ->
        {:ok,
         %{
           channel: info.aggregate |> String.downcase(),
           topic: info.description,
           users: [],
           created: info.inserted_at |> DateTime.to_unix()
         }}

      {:error, what} ->
        {:stop, {:error, what}}
    end
  end

  @impl true
  def handle_cast(
        {:join,
         {user_socket, user_state = %Sencha.Handler.UserState{user_process: user_process}}},
        state = %{users: users, channel: channel, topic: topic, created: created}
      ) do
    if {user_socket, user_process} in users do
      # We're already in the channel?
      {:noreply, state}
    else
      # Add the user to the socket list
      state = %{state | users: [{user_socket, user_process} | users]}

      # Send a join message to everyone
      for {other_socket, _} <- state.users do
        other_socket |> __MODULE__.Helpers.join(state.channel, user_state)
      end

      # Send the channel topic and usernames to whoever just joined
      user_socket
      |> __MODULE__.Helpers.send_topic(channel, user_state, topic, created)
      |> __MODULE__.Helpers.send_names(channel, user_state, state.names)

      # Send channel join acknowledgement to the user's state agent
      Sencha.User.join(user_process, self())

      {:noreply, state}
    end
  end

  @impl true
  def handle_cast(
        {:part,
         {user_socket, user_state = %Sencha.Handler.UserState{user_process: user_process}, reason}},
        state = %{users: users, channel: channel}
      ) do
    if {user_socket, user_process} in users do
      # Notify others about the user leaving
      for {other_socket, _} <- users do
        other_socket |> __MODULE__.Helpers.part(channel, user_state, reason)
      end

      # Send channel part acknowledgement to the user's state agent
      Sencha.User.part(user_process, self())

      # Remove user from the channel socket list
      {:noreply, %{state | users: users |> List.delete({user_socket, user_process})}}
    else
      # We're not in the channel?
      user_socket
      |> __MODULE__.Helpers.not_on_channel(channel, user_state)
    end
  end

  @impl true
  def handle_cast(
        {:quit, {user_socket, %Sencha.Handler.UserState{user_process: user_process}}},
        state = %{users: users}
      ) do
    # The user should have had their quit message sent already by now
    {:noreply, %{state | users: users |> List.delete({user_socket, user_process})}}
  end

  @impl true
  def handle_cast(
        {:talk,
         {user_socket, user_state = %Sencha.Handler.UserState{user_process: user_process},
          message}},
        state = %{users: users, channel: channel}
      ) do
    if {user_socket, user_process} in users do
      # User's in the channel
      for {receiver_socket, receiver_process} <- users do
        # The user sending the message already has it buffered on their IRC
        # client 
        if receiver_process != user_process do
          receiver_socket
          |> __MODULE__.Helpers.talk(channel, user_state, message)
        end
      end
    else
      # User's not in the channel, let's not send the message
      # This isn't up to IRC spec, but we're going to enforce it anymway.
      user_socket
      |> __MODULE__.Helpers.not_on_channel(channel, user_state)
    end

    # Talking on IRC doesn't affect channel state directly
    {:noreply, state}
  end

  @impl true
  def handle_call(:get_users, _from, state = %{users: users}), do: {:reply, users, state}

  @impl true
  def handle_call(:get_name, _from, state = %{channel: channel}), do: {:reply, channel, state}
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
      send(
        {Exsemantica.Gateway, fastest_node},
        {:aggregate_info, self(), aggregate |> String.replace_prefix("#", "")}
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
