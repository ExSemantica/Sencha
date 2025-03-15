defmodule Sencha.Handler.Welcome do
  @moduledoc """
  Handles client connections after SASL and CAP succeed
  """
  require Logger

  defp send_burst({socket, state}) do
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

  def check_for_others({socket, state}, handle) do
    user_status = Sencha.UserSupervisor.start_child(handle, self())

    case user_status do
      {:ok, user_pid} ->
        Logger.debug("#{handle} connects")

        {:cont,
         {socket,
          %Sencha.Handler.UserState{
            state
            | irc_state: :connected,
              connected?: true,
              requested_handle: handle,
              ping_received?: false,
              ping_timer: Process.send_after(self(), :ping, Sencha.Handler.get_ping_interval()),
              timeout_timer: nil,
              user_process: user_pid,
              last_ping: DateTime.utc_now(:second)
          }}
         |> send_burst()}

      {:error, {:already_started, _}} ->
        socket
        |> ThousandIsland.Socket.send(
          %Sencha.Message{
            prefix: Sencha.ApplicationInfo.get_chat_hostname(),
            command: "433",
            params: [handle],
            trailing: "Account already in use"
          }
          |> Sencha.Message.encode()
        )

        {socket, state} |> Sencha.Handler.quit("Account already in use")

        {:halt, {socket, state}}
    end
  end
end
