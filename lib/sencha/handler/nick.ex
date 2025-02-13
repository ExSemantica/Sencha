defmodule Sencha.Handler.Nick do
  @moduledoc """
  Handles nickname passing in IRC.
  """

  def handle(
        %Sencha.Message{command: "NICK", params: [nick]},
        {socket,
         state = %Sencha.Handler.UserState{
           irc_state: :performing_authentication,
           requested_password: nil
         }}
      ) do
    {:cont, {socket, %Sencha.Handler.UserState{state | requested_handle: nick}}}
  end

  def handle(
        %Sencha.Message{command: "NICK", params: [nick]},
        {socket, state = %Sencha.Handler.UserState{irc_state: :performing_authentication}}
      ) do
    {:cont,
     {socket,
      %Sencha.Handler.UserState{state | requested_handle: nick, irc_state: :authentication_ready}}}
  end
end
