defmodule Sencha.Handler.Ping do
  @moduledoc """
  Handles receiving client ping in IRC
  """
  def handle(message = %Sencha.Message{command: "PING"}, {socket, state}) do
    socket
    |> ThousandIsland.Socket.send(
      %Sencha.Message{message | command: "PONG"}
      |> Sencha.Message.encode()
    )

    {:cont, {socket, state}}
  end
end
