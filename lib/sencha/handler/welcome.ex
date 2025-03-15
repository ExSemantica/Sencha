defmodule Sencha.Handler.Welcome do
  @moduledoc """
  Handles client connections after SASL and CAP succeed
  """
  def send_burst({socket, state}) do
    real_handle = state.requested_handle
    host = Sencha.ApplicationInfo.get_chat_hostname()

    refreshed =
      Sencha.ApplicationInfo.get_last_refreshed()
      |> Calendar.strftime("%a, %-d %b %Y %X %Z")

    state.user_process |> Sencha.User.set_modes(["+w"])

    version = Sencha.ApplicationInfo.get_version()

    burst = [
      %Sencha.Message{
        prefix: host,
        command: "001",
        params: [real_handle],
        trailing: "Welcome to Sencha, " <> real_handle
      },
      %Sencha.Message{
        prefix: host,
        command: "002",
        params: [real_handle],
        trailing: "Your host is " <> host <> ", running version v" <> version
      },
      %Sencha.Message{
        prefix: host,
        command: "003",
        params: [real_handle],
        trailing: "This server was last restarted " <> refreshed
      },
      %Sencha.Message{
        prefix: host,
        command: "004",
        params: [real_handle, "sencha", version]
      },
      %Sencha.Message{
        prefix: host,
        command: "422",
        params: [real_handle],
        trailing: "MOTD File is unimplemented"
      }
    ]

    for b <- burst do
      socket |> ThousandIsland.Socket.send(b |> Sencha.Message.encode())
    end

    {socket, state}
  end
end
