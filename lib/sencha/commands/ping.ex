defmodule Sencha.Commands.Ping do
  @moduledoc """
  Handle 'PING' IRCv3 commands
  """
  def handle_irc(
        _pid,
        _packet = %Sencha.Message{params: [lag], trailing: nil},
        {socket, _state}
      ) do
    socket
    |> ThousandIsland.Socket.send(
      Sencha.Message.encode(%Sencha.Message{
        prefix: Application.fetch_env!(:sencha, :host),
        command: "PONG",
        params: [lag]
      })
    )

    :ok
  end

  def handle_irc(_pid, _packet, {_socket, _state}) do
    :ok
  end
end
