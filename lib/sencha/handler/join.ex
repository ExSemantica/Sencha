defmodule Sencha.Handler.Join do
  @moduledoc """
  Handles joining channels in IRC.
  """
  @max_recipients 1

  def handle(pid, %Sencha.Message{params: [channels]}, _socket) do
    channels_list = channels |> String.split(",") |> Enum.uniq()

    if length(channels_list) > @max_recipients do
      send(pid, :too_many)
    else
      send(pid, {:join_these, channels_list})
    end
  end
end
