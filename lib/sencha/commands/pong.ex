defmodule Sencha.Commands.Pong do
  @moduledoc """
  Handle 'PONG' IRCv3 commands
  """
  def handle_irc(
        pid,
        _packet = %Sencha.Message{trailing: server},
        {_socket, _state = %Sencha.Handler.UserState{authentication_state: :ok, timeout_ping: ping, timeout_ping_hard: hard}}
      ) do
    if server == Application.fetch_env!(:sencha, :host) do
      Process.cancel_timer(ping)
      Process.cancel_timer(hard)

      :ok = Sencha.Handler.receive_ping(pid)
    end

    :ok
  end

  def handle_irc(_pid, _packet, {_socket, _state}) do
    :ok
  end
end
