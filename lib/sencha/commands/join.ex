defmodule Sencha.Commands.Join do
  @moduledoc """
  Handle 'JOIN' IRCv3 commands
  """
  def max_targets(), do: 4

  def handle_irc(
        _pid,
        _packet = %Sencha.Message{params: [channels_sep]},
        {_socket,
         _state = %Sencha.Handler.UserState{
           nickname: nickname,
           user_process: user,
           authentication_state: :ok
         }}
      ) do
    channels = String.split(channels_sep, ",")

    if length(channels) > max_targets() do
      Sencha.Handler.send_message(user, %Sencha.Message{
        prefix: Application.fetch_env!(:sencha, :host),
        command: "407",
        params: [nickname],
        trailing: "You have specified too many targets"
      })
    else
      for channel <- channels do
        Sencha.User.join(user, channel)
      end
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
