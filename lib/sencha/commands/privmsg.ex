defmodule Sencha.Commands.Privmsg do
  @moduledoc """
  Handle 'PRIVMSG' IRCv3 commands
  """

  def handle_irc(
        pid,
        packet = %Sencha.Message{params: ["#" <> _channel], trailing: message},
        {_socket,
         _state = %Sencha.Handler.UserState{
           nickname: nickname,
           user_process: user,
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
      {:ok, ustate} = Sencha.User.get_state(user)

      Sencha.Channel.send_message(channel, user, %Sencha.Message{
        prefix: Sencha.User.State.hostmask(ustate),
        command: "PRIVMSG",
        params: [channame],
        trailing: message
      })
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
