defmodule Sencha.Channel.Names do
  @moduledoc """
  Conveniences for listing users of a `Sencha.Channel`.
  """

  @doc """
  Send the names list to a user given a `Sencha.Channel.State` and the user's
  `Sencha.User.State`.

  Set myself to nil if this is an execution of a 'NAMES' command.
  Set myself to the joiner PID if sending the joining notification otherwise.
  """
  def send(
        channel = %Sencha.Channel.State{modes: modes},
        ustate = %Sencha.User.State{},
        myself \\ nil
      ) do
    users =
      if is_nil(myself) do
        channel.users
      else
        [myself | channel.users]
      end

    owner = Sencha.Repo.get(Sencha.Repo.User, channel.owner)

    {_, mapped} =
      users
      |> Enum.map_reduce(%{?_ => [], ?@ => ["Services"], ?+ => []}, fn user_pid, acc ->
        {:ok, state} = Sencha.User.get_state(user_pid)
        user = state.nickname

        {user_pid,
         cond do
           ("~u " <> user) in channel.modes[?o] or user == owner.nickname ->
             update_in(acc, [?@], fn opers -> [user | opers] end)

           ("~u " <> user) in channel.modes[?v] ->
             update_in(acc, [?+], fn voices -> [user | voices] end)

           true ->
             update_in(acc, [?_], fn regulars -> [user | regulars] end)
         end}
      end)

    spaced =
      [
        mapped[?@] |> Enum.map(&("@" <> &1)) |> Enum.sort(),
        mapped[?+] |> Enum.map(&("+" <> &1)) |> Enum.sort(),
        mapped[?_] |> Enum.sort()
      ]
      |> List.flatten()
      |> Enum.join(" ")

    if modes[?s] do
      Sencha.Handler.send_message(ustate.handler_process, %Sencha.Message{
        prefix: Application.fetch_env!(:sencha, :host),
        command: "353",
        params: [ustate.nickname, "@", channel.name],
        trailing: spaced
      })
    else
      Sencha.Handler.send_message(ustate.handler_process, %Sencha.Message{
        prefix: Application.fetch_env!(:sencha, :host),
        command: "353",
        params: [ustate.nickname, "=", channel.name],
        trailing: spaced
      })
    end

    send_ending(channel.name, ustate)
  end

  @doc """
  Send the ending numeric
  """
  def send_ending(name, ustate) do
    Sencha.Handler.send_message(ustate.handler_process, %Sencha.Message{
      prefix: Application.fetch_env!(:sencha, :host),
      command: "366",
      params: [ustate.nickname, name],
      trailing: "End of /NAMES list"
    })
  end
end
