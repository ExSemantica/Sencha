defmodule Sencha.Handler.Ping do
  @moduledoc """
  Handles receiving client PING messages in IRC

  The server sends the client's message back, except with "PONG" as the command
  """
  def handle(_pid, message, socket) do
    socket
    |> ThousandIsland.Socket.send(
      %Sencha.Message{
        message
        | command: "PONG"
      }
      |> Sencha.Message.encode()
    )
  end
end
