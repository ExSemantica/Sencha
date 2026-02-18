defmodule Sencha.Commands.Motd do
  @moduledoc """
  Handle 'MOTD' IRCv3 commands
  """
  def handle_irc(pid, packet = %Sencha.Message{params: []}, {socket, state}) do
    handle_irc(
      pid,
      %Sencha.Message{packet | params: [Application.fetch_env!(:sencha, :host)]},
      {socket, state}
    )
  end

  def handle_irc(
        _pid,
        _packet = %Sencha.Message{params: [server]},
        {socket, state}
      ) do
    if server == Application.fetch_env!(:sencha, :host) do
      Sencha.Handler.Welcome.send_motd({socket, state})
    end

    :ok
  end

  def handle_irc(_pid, _packet, {_socket, _state}) do
    :ok
  end
end
