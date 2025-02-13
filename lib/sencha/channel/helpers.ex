defmodule Sencha.Channel.Helpers do
  @moduledoc """
  Convenience functions to de-clutter `Sencha.Channel`.
  """
  def join(socket, channel, user) do
    socket
    |> ThousandIsland.Socket.send(
      %Sencha.Message{
        prefix: Sencha.Handler.UserState.get_host_mask(user),
        command: "JOIN",
        params: [channel],
        trailing: "ExSemantica User"
      }
      |> Sencha.Message.encode()
    )

    socket
  end

  def part(socket, channel, user, reason) do
    socket
    |> ThousandIsland.Socket.send(
      %Sencha.Message{
        prefix: Sencha.Handler.UserState.get_host_mask(user),
        command: "PART",
        params: [channel],
        trailing: reason
      }
      |> Sencha.Message.encode()
    )

    socket
  end

  def talk(socket, channel, user, message) do
    socket
    |> ThousandIsland.Socket.send(
      %Sencha.Message{
        prefix: Sencha.Handler.UserState.get_host_mask(user),
        command: "PRIVMSG",
        params: [channel],
        trailing: message
      }
      |> Sencha.Message.encode()
    )

    socket
  end

  def send_names(
        socket,
        channel,
        %Sencha.Handler.UserState{requested_handle: requested_handle},
        everyone
      ) do
    handles =
      everyone
      |> Enum.map(fn {_socket, user_process} ->
        Sencha.User.get_handle(user_process)
      end)

    handles = ["@Services" | handles]

    server_name = Sencha.ApplicationInfo.get_chat_hostname()

    burst = [
      %Sencha.Message{
        prefix: server_name,
        command: "353",
        params: [requested_handle, "=", channel],
        trailing: handles |> Enum.join(" ")
      },
      %Sencha.Message{
        prefix: server_name,
        command: "366",
        params: [requested_handle, channel],
        trailing: "End of /NAMES list"
      }
    ]

    for b <- burst do
      socket |> ThousandIsland.Socket.send(b |> Sencha.Message.encode())
    end

    socket
  end

  def send_topic(
        socket,
        channel,
        %Sencha.Handler.UserState{requested_handle: requested_handle},
        topic,
        refreshed
      ) do
    server_name = Sencha.ApplicationInfo.get_chat_hostname()

    burst = [
      %Sencha.Message{
        prefix: server_name,
        command: "332",
        params: [requested_handle, channel],
        trailing: topic
      },
      %Sencha.Message{
        prefix: server_name,
        command: "333",
        params: [requested_handle, channel, "Services", refreshed]
      }
    ]

    for b <- burst do
      socket |> ThousandIsland.Socket.send(b |> Sencha.Message.encode())
    end

    socket
  end

  def not_on_channel(socket, channel, %Sencha.Handler.UserState{
        requested_handle: requested_handle
      }) do
    socket
    |> ThousandIsland.Socket.send(
      %Sencha.Message{
        prefix: Sencha.ApplicationInfo.get_chat_hostname(),
        command: "442",
        params: [requested_handle, channel],
        trailing: "You're not on that channel"
      }
      |> Sencha.Message.encode()
    )

    socket
  end
end
