defmodule Sencha.Handler.Welcome do
  @moduledoc """
  Sends a welcome burst to a client
  """
  def send_burst({socket, state}) do
    real_handle = state.requested_handle

    refreshed =
      Sencha.ApplicationInfo.get_last_refreshed()
      |> Calendar.strftime("%a, %-d %b %Y %X %Z")

    user_status_pid |> Sencha.User.set_modes(["+w"])

    version = Sencha.ApplicationInfo.get_version()

    burst = [
      %Sencha.Message{
        prefix: host,
        command: "900",
        params: [real_handle],
        trailing: "You are now logged in as #{real_handle}"
      },
      %Sencha.Message{
        prefix: host,
        command: "903",
        params: [real_handle],
        trailing: "SASL authentication successful"
      },
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
