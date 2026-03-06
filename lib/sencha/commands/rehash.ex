defmodule Sencha.Commands.Rehash do
  @moduledoc """
  Handle 'REHASH' IRCv3 commands
  """

  def handle_irc(
        _pid,
        _packet = %Sencha.Message{params: [], trailing: nil},
        {socket,
         _state = %Sencha.Handler.UserState{
           nickname: nickname,
           user_process: user,
           authentication_state: :ok
         }}
      ) do
    {:ok, ustate} = Sencha.User.get_state(user)

    if MapSet.member?(ustate.modes, ?o) do
      socket
      |> ThousandIsland.Socket.send(
        Sencha.Message.encode(%Sencha.Message{
          prefix: Application.fetch_env!(:sencha, :host),
          command: "382",
          params: [nickname, Application.app_dir(:sencha, "priv")],
          trailing: "Rehashing"
        })
      )

      Sencha.rehash()
    else
      socket
      |> ThousandIsland.Socket.send(
        Sencha.Message.encode(%Sencha.Message{
          prefix: Application.fetch_env!(:sencha, :host),
          command: "481",
          params: [nickname],
          trailing: "Can not rehash, user is not IRC operator"
        })
      )
    end

    :ok
  end

  def handle_irc(
        _pid,
        _packet,
        {_socket, _state}
      ) do
    :ok
  end
end
