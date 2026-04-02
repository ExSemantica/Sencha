defmodule Sencha.Commands.Lusers do
  @moduledoc """
  Handle 'LUSERS' IRCv3 commands
  """

  def handle_irc(
        _pid,
        _packet = %Sencha.Message{params: []},
        {_socket,
         _state = %Sencha.Handler.UserState{authentication_state: :ok, user_process: user}}
      ) do
    Sencha.User.send_lusers(user)

    :ok
  end

  def handle_irc(_pid, _packet, {_socket, _state}) do
    :ok
  end
end
