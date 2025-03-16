defmodule Sencha.Handler.Privmsg do
  @moduledoc """
  Handles messaging users and channels in IRC.
  """
  @max_recipients 1

  # Some other IRC clients do NOT comply, let's fix that...
  def handle(pid, message = %Sencha.Message{params: [user, one_word], trailing: nil}, socket) do
    handle(pid, %Sencha.Message{message | params: [user], trailing: one_word}, socket)
  end

  def handle(pid, %Sencha.Message{params: [recipients], trailing: message}, _socket) do
    recipients_list = recipients |> String.split(",") |> Enum.uniq()

    if length(recipients_list) > @max_recipients do
      send(pid, :too_many)
    else
      send(pid, {:message_these, recipients, message})
    end
  end
end
