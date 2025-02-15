defmodule Sencha.Handler.Pass do
  @moduledoc """
  Handles password sending in IRC
  """
  # Some noncompliant clients will send the password in the trailing parameters
  def handle(
        %Sencha.Message{command: "PASS", trailing: password},
        {socket,
         state = %Sencha.Handler.UserState{
           irc_state: :performing_authentication,
           requested_handle: nil
         }}
      ) do
    {:cont, {socket, %Sencha.Handler.UserState{state | requested_password: password}}}
  end

  def handle(
        %Sencha.Message{command: "PASS", trailing: password},
        {socket, state = %Sencha.Handler.UserState{irc_state: :performing_authentication}}
      ) do
    {:cont,
     {socket,
      %Sencha.Handler.UserState{
        state
        | irc_state: :authentication_ready,
          requested_password: password
      }}}
  end

  # Compliant ones:
  def handle(
        %Sencha.Message{command: "PASS", params: [password]},
        {socket,
         state = %Sencha.Handler.UserState{
           irc_state: :performing_authentication,
           requested_handle: nil
         }}
      ) do
    {:cont, {socket, %Sencha.Handler.UserState{state | requested_password: password}}}
  end

  def handle(
        %Sencha.Message{command: "PASS", params: [password]},
        {socket, state = %Sencha.Handler.UserState{irc_state: :performing_authentication}}
      ) do
    {:cont,
     {socket,
      %Sencha.Handler.UserState{
        state
        | irc_state: :authentication_ready,
          requested_password: password
      }}}
  end
end
