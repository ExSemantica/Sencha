defmodule Sencha.Handler.Privmsg do
  @moduledoc """
  Handles joining channels in IRC.
  """
  require Logger

  @regex_ctcp_action ~r/\x01ACTION (?<action>.+)\x01/

  @max_recipients 1

  def handle(
        %Sencha.Message{command: "PRIVMSG", params: [recipients_commas], trailing: message},
        {socket,
         state = %Sencha.Handler.UserState{
           requested_handle: handle,
           connected?: true
         }}
      ) do
    recipients = recipients_commas |> String.split(",") |> Enum.uniq()

    do_recipients(socket, state, handle, recipients, message)

    {:cont, {socket, state}}
  end

  defp do_recipients(socket, _state, handle, recipients, _message)
       when length(recipients) > @max_recipients do
    socket
    |> ThousandIsland.Socket.send(
      %Sencha.Message{
        prefix: Sencha.ApplicationInfo.get_chat_hostname(),
        command: "407",
        params: [handle],
        trailing: "Too many recipients"
      }
      |> Sencha.Message.encode()
    )
  end

  defp do_recipients(socket, state, handle, recipients, message) do
    for recipient <- recipients do
      if recipient |> String.starts_with?("#") do
        channel_stat = Registry.lookup(Sencha.ChannelRegistry, recipient)

        case channel_stat do
          [{pid, _}] ->
            format_message(recipient, handle, message)
            Sencha.Channel.talk(pid, {socket, state}, message)

          [] ->
            socket
            |> ThousandIsland.Socket.send(
              %Sencha.Message{
                prefix: Sencha.ApplicationInfo.get_chat_hostname(),
                command: "403",
                params: [handle, recipient],
                trailing: "No such aggregate"
              }
              |> Sencha.Message.encode()
            )
        end
      else
        user_stat = Registry.lookup(Sencha.ChannelRegistry, recipient)

        case user_stat do
          [{pid, _}] ->
            format_message(recipient, handle, message)
            Sencha.User.send(pid, {socket, state}, message)

          [] ->
            socket
            |> ThousandIsland.Socket.send(
              %Sencha.Message{
                prefix: Sencha.ApplicationInfo.get_chat_hostname(),
                command: "401",
                params: [handle, recipient],
                trailing: "No such user"
              }
              |> Sencha.Message.encode()
            )
        end
      end
    end
  end

  defp format_message(recipient, handle, message) do
    if message =~ @regex_ctcp_action do
      converted = Regex.named_captures(@regex_ctcp_action, message)
      Logger.debug("[#{recipient}] * #{handle} #{converted["action"]}")
    else
      Logger.debug("[#{recipient}] <#{handle}> #{message}")
    end
  end
end
