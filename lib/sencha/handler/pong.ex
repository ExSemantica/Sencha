defmodule Sencha.Handler.Pong do
  @moduledoc """
  Handles receiving client pong in IRC
  """
  def handle(
        %Sencha.Message{command: "PONG"},
        {socket,
         state = %Sencha.Handler.UserState{
           ping_received?: false
         }}
      ) do
    {:cont, {socket, %Sencha.Handler.UserState{state | ping_received?: true}}}
  end
end
