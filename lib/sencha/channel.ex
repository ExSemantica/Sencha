defmodule Sencha.Channel do
  @moduledoc """
  TODO: clean this code up
  """
  use GenServer

  # ===========================================================================
  # Public callbacks
  # ===========================================================================
  @doc """
  Start a channel process. This occurs after a user joins the channel.

  If the user specifies '/JOIN ##test' then the '##test' global gets registered.
  """
  def start_link(args = %{name: name}) do
    GenServer.start_link(__MODULE__, args, name: {:global, name})
  end

  @doc """
  Gets this channel's state.
  """
  def get_state(pid) do
    GenServer.call(pid, :get_state)
  end

  @doc """
  Changes this channel's registration flag
  """
  def mark_registered(pid, registered?) do
    GenServer.cast(pid, {:mark_registered, registered?})
  end

  @doc """
  Changes this channel's `Sencha.Repo.User` owner
  """
  def mark_owner(pid, owner) do
    GenServer.cast(pid, {:mark_owner, owner})
  end

  @doc """
  Sends a `Sencha.Message` to other users

  This can be used for 'PRIVMSG' and 'NOTICE' messages

  If channel mode 'n' is set, then the user must be in the channel for this to
  work
  """
  def send_message(pid, user_pid, message) do
    GenServer.cast(pid, {:send_message, user_pid, message})
  end

  @doc """
  Handles a 'JOIN' from a `Sencha.User`.
  """
  def user_join(pid, user_pid) do
    GenServer.cast(pid, {:user_join, user_pid})
  end

  @doc """
  Handles a 'PART' from a `Sencha.User`.
  """
  def user_part(pid, user_pid, reason) do
    GenServer.cast(pid, {:user_part, user_pid, reason})
  end

  @doc """
  Accumulate the `Sencha.User` processes into a `MapSet` for 'QUIT' messages.
  """
  def users_accumulate(pid) do
    GenServer.call(pid, :users_accumulate)
  end

  @doc """
  Cleanly removes this user process from the channel.
  """
  def user_remove(pid, user_pid) do
    GenServer.cast(pid, {:user_remove, user_pid})
  end

  @doc """
  Handles a 'PART' from a `Sencha.User`.
  """
  def set_topic(pid, username, topic) do
    GenServer.cast(pid, {:set_topic, username, topic})
  end

  # ===========================================================================
  # Behavioral callbacks (initialization)
  # ===========================================================================
  @impl GenServer
  def init(%{name: name, joiner: joiner}) do
    case __MODULE__.State.init(name, joiner) do
      {:ok, state} ->
        {:ok, state}

      {:error, reason = {:locked, _channel, _locked_reason}} ->
        {:stop, reason}
    end
  end

  # ===========================================================================
  # Behavioral callbacks (calling messages)
  # ===========================================================================
  @impl GenServer
  def handle_call(:get_state, _from, state) do
    {:reply, {:ok, state}, state}
  end

  @impl GenServer
  def handle_call(:users_accumulate, _from, state = %__MODULE__.State{users: users}) do
    {:reply, {:ok, MapSet.new(users)}, state}
  end

  # ===========================================================================
  # Behavioral callbacks (casting messages)
  # ===========================================================================
  @impl GenServer
  def handle_cast({:mark_registered, registered?}, state = %__MODULE__.State{}) do
    {:noreply, %__MODULE__.State{state | registered?: registered?}}
  end

  @impl GenServer
  def handle_cast({:mark_owner, owner}, state = %__MODULE__.State{}) do
    {:noreply, %__MODULE__.State{state | owner: owner}}
  end

  @impl GenServer
  def handle_cast(
        {:send_message, user_pid, message = %Sencha.Message{}},
        state = %__MODULE__.State{modes: modes, users: users, name: name}
      ) do
    cond do
      modes[?n] and user_pid not in users ->
        {:ok, ustate} = Sencha.User.get_state(user_pid)

        Sencha.Handler.send_message(ustate.handler_process, %Sencha.Message{
          prefix: Application.fetch_env!(:sencha, :host),
          command: "404",
          params: [ustate.nickname, name],
          trailing: "Cannot send to channel"
        })

      true ->
        {:ok, ustate} = Sencha.User.get_state(user_pid)
        uhost = ustate |> Sencha.User.State.hostmask()
        users_no_send = users |> Enum.reject(&(&1 == user_pid))

        for receiver_pid <- users_no_send do
          {:ok, receiver} = Sencha.User.get_state(receiver_pid)

          Sencha.Handler.send_message(receiver.handler_process, %Sencha.Message{
            prefix: uhost,
            command: message.command,
            params: [name],
            trailing: message.trailing
          })
        end
    end

    {:noreply, state}
  end

  @impl GenServer
  def handle_cast(
        {:user_join, user_pid},
        state = %__MODULE__.State{
          users: users,
          name: name
        }
      ) do
    cond do
      # TODO: Separate the join burst into its own module?
      user_pid not in users ->
        {:ok, ustate} = Sencha.User.get_state(user_pid)

        Sencha.Handler.send_message(ustate.handler_process, %Sencha.Message{
          prefix: ustate |> Sencha.User.State.hostmask(),
          command: "JOIN",
          params: [name]
        })

        __MODULE__.Topic.send(state, ustate)
        __MODULE__.Names.send(state, ustate, user_pid)

        uhost = ustate |> Sencha.User.State.hostmask()

        owner = Sencha.Repo.get(Sencha.Repo.User, state.owner)
        owner? = ustate.nickname == owner.nickname

        for receiver_pid <- users do
          {:ok, receiver} = Sencha.User.get_state(receiver_pid)

          Sencha.Handler.send_message(receiver.handler_process, %Sencha.Message{
            prefix: uhost,
            command: "JOIN",
            params: [name]
          })

          if owner? do
            Sencha.Handler.send_message(receiver.handler_process, %Sencha.Message{
              prefix: "Services!~Services@" <> Application.fetch_env!(:sencha, :host),
              command: "MODE",
              params: [name, "+o", owner.nickname]
            })
          end
        end

        if owner? do
          Sencha.Handler.send_message(ustate.handler_process, %Sencha.Message{
            prefix: "Services!~Services@" <> Application.fetch_env!(:sencha, :host),
            command: "MODE",
            params: [name, "+o", owner.nickname]
          })
        end

        {:noreply, %__MODULE__.State{state | users: [user_pid | users]}}

      true ->
        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_cast(
        {:user_part, user_pid, reason},
        state = %__MODULE__.State{
          users: users,
          name: name
        }
      ) do
    {:ok, ustate} = Sencha.User.get_state(user_pid)

    cond do
      user_pid in users ->
        uhost = ustate |> Sencha.User.State.hostmask()

        for receiver_pid <- users do
          {:ok, receiver} = Sencha.User.get_state(receiver_pid)

          Sencha.Handler.send_message(receiver.handler_process, %Sencha.Message{
            prefix: uhost,
            command: "PART",
            params: [name],
            trailing: reason
          })
        end

        {:noreply, %__MODULE__.State{state | users: List.delete(users, user_pid)}}

      true ->
        Sencha.Handler.send_message(ustate.handler_process, %Sencha.Message{
          prefix: Application.fetch_env!(:sencha, :host),
          command: "442",
          params: [ustate.nickname, name],
          trailing: "You're not on that channel"
        })

        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_cast(
        {:user_remove, user_pid},
        state = %__MODULE__.State{
          users: users
        }
      ) do
    {:noreply, %__MODULE__.State{state | users: List.delete(users, user_pid)}}
  end

  @impl GenServer
  def handle_cast({:set_topic, username, topic}, state = %__MODULE__.State{}) do
    state = %__MODULE__.State{
      state
      | topic: topic,
        topic_set_by: username,
        topic_set: DateTime.utc_now()
    }

    state |> save()

    {:noreply, state}
  end

  # ===========================================================================
  defp save(state = %__MODULE__.State{registered?: true, modes: modes}) do
    %Sencha.Repo.Channel{
      name: state.name,
      topic: state.topic,
      topic_set: state.topic_set,
      topic_set_by: state.topic_set_by
    }
    |> Sencha.Channel.Modes.update(modes)
    |> Ecto.Changeset.change()
    |> Sencha.Repo.update()
  end

  defp save(_state) do
    # Don't save unregistered channels
    {:error, :unregistered}
  end
end
