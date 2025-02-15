defmodule Sencha.Handler.Join do
  @moduledoc """
  Handles joining channels in IRC.
  """
  require Logger

  @max_recipients 5

  def handle(
        %Sencha.Message{command: "JOIN", params: [channels_commas]},
        {socket,
         state = %Sencha.Handler.UserState{
           requested_handle: handle,
           connected?: true
         }}
      ) do
    channels = channels_commas |> String.split(",") |> Enum.uniq()

    do_recipients(socket, state, handle, channels)

    {:cont, {socket, state}}
  end

  defp do_recipients(socket, _state, handle, channels)
       when length(channels) > @max_recipients do
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

  defp do_recipients(socket, state, handle, channels) do
    for channel <- channels do
      join_stat = Sencha.ChannelSupervisor.start_child(channel)

      case join_stat do
        {:ok, pid} ->
          Logger.debug("#{handle} joins channel #{channel}")
          Sencha.Channel.join(pid, {socket, state})

        {:error, {:already_started, pid}} ->
          Logger.debug("#{handle} joins channel #{channel}")
          Sencha.Channel.join(pid, {socket, state})

        {:error, :no_such_item} ->
          socket
          |> ThousandIsland.Socket.send(
            %Sencha.Message{
              prefix: Sencha.ApplicationInfo.get_chat_hostname(),
              command: "403",
              params: [handle, channel],
              trailing: "No such aggregate"
            }
            |> Sencha.Message.encode()
          )
      end
    end
  end
end
