defmodule Sencha.Commands.Quit do
  @moduledoc """
  Handle 'QUIT' IRCv3 commands
  """

  def handle_irc(
        _pid,
        _packet = %Sencha.Message{trailing: nil},
        {_socket,
         _state = %Sencha.Handler.UserState{
           user_process: user,
           authentication_state: :ok
         }}
      ) do
    Sencha.User.disconnect(user, "Client Quit")

    :ok
  end

  def handle_irc(
        _pid,
        _packet = %Sencha.Message{trailing: reason},
        {_socket,
         _state = %Sencha.Handler.UserState{
           user_process: user,
           authentication_state: :ok
         }}
      ) do
    Sencha.User.disconnect(user, "Client Quit (#{reason})")

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
