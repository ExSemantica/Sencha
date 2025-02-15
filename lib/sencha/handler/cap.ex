defmodule Sencha.Handler.Cap do
  @moduledoc """
  Handles CAP capability passing in IRC.
  """

  def handle(
        %Sencha.Message{command: "CAP", params: negotiate},
        {socket,
         state = %Sencha.Handler.UserState{
           connected?: false
         }}
      )
      when hd(negotiate) == "LS" do
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
end
