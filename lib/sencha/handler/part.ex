defmodule Sencha.Handler.Part do
  @moduledoc """
  Handles leaving channels in IRC.
  """
  require Logger

  @max_recipients 5

  def handle(
        %Sencha.Message{command: "PART", params: [channels_commas], trailing: reason},
        {socket,
         state = %Sencha.Handler.UserState{
           requested_handle: handle,
           connected?: true
         }}
      ) do
    channels = channels_commas |> String.split(",") |> Enum.uniq()

    do_recipients(socket, state, handle, channels, reason)

    {:cont, {socket, state}}
  end

  defp do_recipients(socket, _state, handle, channels, _reason)
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

  defp do_recipients(socket, state, handle, channels, reason) do
    for channel <- channels do
      channel_stat = Registry.lookup(Sencha.ChannelRegistry, channel)

      case channel_stat do
        [{pid, _}] ->
          Logger.debug("#{handle} leaves channel #{channel} (#{reason})")
          Sencha.Channel.part(pid, {socket, state}, reason)

        [] ->
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
