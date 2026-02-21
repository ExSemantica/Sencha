defmodule Sencha.Commands.Motd do
  @moduledoc """
  Handle 'MOTD' IRCv3 commands
  """
  def handle_irc(
        pid,
        packet = %Sencha.Message{params: []},
        {socket, state = %Sencha.Handler.UserState{authentication_state: :ok}}
      ) do
    handle_irc(
      pid,
      %Sencha.Message{packet | params: [Application.fetch_env!(:sencha, :host)]},
      {socket, state}
    )
  end

  def handle_irc(
        _pid,
        _packet = %Sencha.Message{params: [server]},
        {_socket, _state = %Sencha.Handler.UserState{authentication_state: :ok, user_process: user}}
      ) do
    if server == Application.fetch_env!(:sencha, :host) do
      Sencha.User.send_motd(user)
    end

    :ok
  end

  def handle_irc(_pid, _packet, {_socket, _state}) do
    :ok
  end
end
