defmodule Sencha.Handler.Privmsg do
  @moduledoc """
  Handles messaging users and channels in IRC.
  """
  require Logger

  @max_recipients 1

  # Some other IRC clients do NOT comply, let's fix that...
  def handle(pid, message = %Sencha.Message{params: [user, one_word], trailing: nil}, socket) do
    handle(pid, %Sencha.Message{message | params: [user], trailing: one_word}, socket)
  end

  def handle(pid, %Sencha.Message{params: [recipients], trailing: message}, socket) do
    recipients_list = recipients |> String.split(",") |> Enum.uniq()

    if length(recipients_list) > @max_recipients do
      {:ok, sender} = Sencha.Handler.get_username(pid)

      socket
      |> Sencha.Numerics.send(407, nickname: sender)
    else
      on_message(pid, socket, recipients_list, message)
    end
  end

  defp on_message(pid, socket, [recipient | recipients], message) do
    channel? = recipient |> String.starts_with?("#")
    {:ok, sender} = Sencha.Handler.get_username(pid)

    if channel? do
      on_channel_message(pid, socket, recipient, sender, message)
    else
      on_user_message(pid, socket, recipient, sender, message)
    end

    on_message(pid, socket, recipients, message)
  end

  defp on_message(_, _, [], _), do: :ok

  defp on_user_message(pid, socket, recipient, sender, message) do
    case Sencha.UserPool.get_socket(recipient) do
      nil ->
        socket
        |> Sencha.Numerics.send(401, nickname: sender, recipient: recipient)

      recipient_pid ->
        {:ok, hostmask} = Sencha.Handler.get_hostmask(pid)
        Sencha.Handler.on_privmsg(recipient_pid, sender, hostmask, message)
    end
  end

  defp on_channel_message(pid, socket, recipient, sender, message) do
    case Registry.lookup(Sencha.ChannelRegistry, recipient) do
      [] ->
        socket
        |> Sencha.Numerics.send(403, nickname: sender, recipient: recipient)

      [{recipient_pid, _}] ->
        Sencha.Channel.talk(recipient_pid, sender, pid, message)
    end
  end
end
