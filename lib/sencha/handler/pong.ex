defmodule Sencha.Handler.Pong do
  @moduledoc """
  Handles receiving client PONG in IRC
  """
  def handle(pid, _message, _socket) do
    # All that needs to be done is to send the ping acknowledge message to the
    # socket PID
    send(pid, :ping_acknowledged)
  end
end
