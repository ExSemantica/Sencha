defmodule Sencha.Commands.Mode do
  @moduledoc """
  Handle 'MODE' IRCv3 commands
  """
  def handle_irc(
        pid,
        packet = %Sencha.Message{params: ["#" <> _channel], trailing: nil},
        {_socket,
         _state = %Sencha.Handler.UserState{
           nickname: nickname,
           authentication_state: :ok
         }}
      ) do
    [channame] = packet.params
    [channame | _unimplemented] = channame |> String.split(",")

    channel = GenServer.whereis({:global, channame})

    if is_nil(channel) do
      Sencha.Handler.send_message(pid, %Sencha.Message{
        prefix: Application.fetch_env!(:sencha, :host),
        command: "403",
        params: [nickname, channame],
        trailing: "No such channel"
      })
    else
      {:ok, %Sencha.Channel.State{modes: modemap}} = Sencha.Channel.get_state(channel)
      modes = Sencha.Channel.Modes.unparse(modemap)

      Sencha.Handler.send_message(pid, %Sencha.Message{
        prefix: Application.fetch_env!(:sencha, :host),
        command: "324",
        params: [[nickname, " ", channame] | modes]
      })
    end

    :ok
  end

  def handle_irc(
        pid,
        _packet = %Sencha.Message{params: [my_nickname | modes_list], trailing: nil},
        {_socket,
         _state = %Sencha.Handler.UserState{
           nickname: nickname,
           user_process: user,
           authentication_state: :ok
         }}
      )
      when nickname == my_nickname do
    {:ok, ustate} = Sencha.User.get_state(user)

    # Loop and then flatten through every MODE argument the client sent.
    unknowns =
      modes_list
      |> Enum.flat_map(fn modes ->
        modechar = modes |> to_charlist()

        case modechar do
          [?+ | modechar_tail] ->
            grantable = Sencha.User.Modes.get_grantables(modechar_tail)

            if MapSet.size(grantable) > 0 do
              Sencha.User.set_modes(user, MapSet.union(ustate.modes, grantable))
            end

            Sencha.User.Modes.get_nonexistants(modechar_tail)

          [?- | modechar_tail] ->
            grantable = Sencha.User.Modes.get_grantables(modechar_tail)

            if MapSet.size(grantable) > 0 do
              Sencha.User.set_modes(user, MapSet.difference(ustate.modes, grantable))
            end

            Sencha.User.Modes.get_nonexistants(modechar_tail)

          [] ->
            Sencha.User.Modes.send_to_client(ustate)
            []

          _ ->
            []
        end
      end)

    if unknowns != [] do
      Sencha.Handler.send_message(pid, %Sencha.Message{
        prefix: Application.fetch_env!(:sencha, :host),
        command: "501",
        params: [nickname],
        trailing: "Unknown MODE flag"
      })
    end

    :ok
  end

  def handle_irc(
        pid,
        _packet = %Sencha.Message{params: params, trailing: nil},
        {_socket,
         _state = %Sencha.Handler.UserState{
           nickname: nickname,
           authentication_state: :ok
         }}
      )
      when params != [] do
    Sencha.Handler.send_message(pid, %Sencha.Message{
      prefix: Application.fetch_env!(:sencha, :host),
      command: "502",
      params: [nickname],
      trailing: "Can't view/change modes of other users"
    })

    :ok
  end

  def handle_irc(_pid, _packet, {_socket, _state}) do
    :ok
  end
end
