defmodule Sencha.Commands.Pong do
  @moduledoc """
  Handle 'PONG' IRCv3 commands
  """
  def handle_irc(pid, packet = %Sencha.Message{params: [server]}, {socket, state}) do
    # some IRC clients don't abide by the specs (see `Sencha.Commands.Cap`)
    handle_irc(pid, %Sencha.Message{packet | trailing: server}, {socket, state})
  end

  def handle_irc(
        _pid,
        _packet = %Sencha.Message{trailing: server},
        {_socket,
         _state = %Sencha.Handler.UserState{authentication_state: :ok, user_process: user}}
      ) do
    if server == Application.fetch_env!(:sencha, :host) do
      Sencha.User.receive_ping(user)
    end

    :ok
  end

  def handle_irc(_pid, _packet, {_socket, _state}) do
    :ok
  end
end
