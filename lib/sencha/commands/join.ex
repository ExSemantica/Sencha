defmodule Sencha.Commands.Join do
  @moduledoc """
  Handle 'JOIN' IRCv3 commands
  """

  def handle_irc(
        _pid,
        _packet = %Sencha.Message{params: [channels_sep]},
        {_socket,
         _state = %Sencha.Handler.UserState{
           user_process: user,
           authentication_state: :ok
         }}
      ) do
    channels = String.split(channels_sep, ",")

    for channel <- channels do
      Sencha.User.join(user, channel)
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
