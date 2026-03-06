defmodule Sencha.Channel do
  @moduledoc """
  TODO: clean this code up
  """
  use GenServer, restart: :temporary

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
          name: name,
          topic: topic,
          topic_set: topic_set,
          topic_set_by: topic_set_by
        }
      ) do
    cond do
      user_pid not in users ->
        {:ok, ustate} = Sencha.User.get_state(user_pid)

        Sencha.Handler.send_message(ustate.handler_process, %Sencha.Message{
          prefix: ustate |> Sencha.User.State.hostmask(),
          command: "JOIN",
          params: [name]
        })

        Sencha.Handler.send_message(ustate.handler_process, %Sencha.Message{
          prefix: Application.fetch_env!(:sencha, :host),
          command: "332",
          params: [ustate.nickname, name],
          trailing: topic
        })

        Sencha.Handler.send_message(ustate.handler_process, %Sencha.Message{
          prefix: Application.fetch_env!(:sencha, :host),
          command: "333",
          params: [
            ustate.nickname,
            name,
            topic_set_by,
            topic_set |> DateTime.to_unix() |> to_string
          ],
          trailing: topic
        })

        Sencha.Handler.send_message(ustate.handler_process, %Sencha.Message{
          prefix: Application.fetch_env!(:sencha, :host),
          command: "353",
          params: [ustate.nickname, "=", name],
          trailing: [user_pid | users] |> calculate_names(state)
        })

        Sencha.Handler.send_message(ustate.handler_process, %Sencha.Message{
          prefix: Application.fetch_env!(:sencha, :host),
          command: "366",
          params: [ustate.nickname, name],
          trailing: "End of /NAMES list"
        })

        uhost = ustate |> Sencha.User.State.hostmask()

        for receiver_pid <- users do
          {:ok, receiver} = Sencha.User.get_state(receiver_pid)

          Sencha.Handler.send_message(receiver.handler_process, %Sencha.Message{
            prefix: uhost,
            command: "JOIN",
            params: [name]
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

  defp calculate_names(user_pids, %__MODULE__.State{modes: modes}) do
    {_users, mapped} =
      user_pids
      |> Enum.map_reduce(%{?_ => [], ?@ => ["Services"], ?+ => []}, fn user_pid, acc ->
        {:ok, state} = Sencha.User.get_state(user_pid)
        user = state.nickname

        {user_pid,
         cond do
           ("~u " <> user) in modes[?o] ->
             update_in(acc, [?@], fn opers -> [user | opers] end)

           ("~u " <> user) in modes[?v] ->
             update_in(acc, [?+], fn voices -> [user | voices] end)

           true ->
             update_in(acc, [?_], fn regulars -> [user | regulars] end)
         end}
      end)

    [
      mapped[?@] |> Enum.map(&("@" <> &1)) |> Enum.sort(),
      mapped[?+] |> Enum.map(&("+" <> &1)) |> Enum.sort(),
      mapped[?_] |> Enum.sort()
    ]
    |> List.flatten()
    |> Enum.join(" ")
  end
end
