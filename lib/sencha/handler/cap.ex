defmodule Sencha.Handler.Cap do
  @moduledoc """
  Handles CAP capability passing in IRC.
  """

  def handle(
        %Sencha.Message{command: "CAP", params: ["LS", "302"]},
        {socket,
         state = %Sencha.Handler.UserState{
           connected?: false
         }}
      ) do
    socket
    |> ThousandIsland.Socket.send(
      %Sencha.Message{
        prefix: Sencha.ApplicationInfo.get_chat_hostname(),
        command: "CAP",
        params: ["*", "LS"],
        trailing: ""
      }
      |> Sencha.Message.encode()
    )

    {:cont, {socket, state}}
  end

  def handle(%Sencha.Message{command: "CAP", params: ["END"]}, {socket, state = %Sencha.Handler.UserState{connected?: false}}) do
    {:cont, {socket, state}}
  end

  def handle(%Sencha.Message{command: "CAP"}, {socket, state}) do
    {:cont, {socket, state}}
  end
end
