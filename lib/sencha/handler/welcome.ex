defmodule Sencha.Handler.Welcome do
  @moduledoc """
  Convenience for sending the welcome burst.
  """
  def do_burst({socket, state = %Sencha.Handler.UserState{nickname: nick}}) do
    socket
    |> ThousandIsland.Socket.send(
      Sencha.Message.encode(%Sencha.Message{
        prefix: Application.fetch_env!(:sencha, :host),
        command: "001",
        params: [nick],
        trailing: "Welcome to Sencha, #{nick}"
      })
    )

    socket
    |> ThousandIsland.Socket.send(
      Sencha.Message.encode(%Sencha.Message{
        prefix: Application.fetch_env!(:sencha, :host),
        command: "002",
        params: [nick],
        trailing:
          "Your host is #{Application.fetch_env!(:sencha, :host)}, running version sencha-#{Application.spec(:sencha)[:vsn]}"
      })
    )

    socket
    |> ThousandIsland.Socket.send(
      Sencha.Message.encode(%Sencha.Message{
        prefix: Application.fetch_env!(:sencha, :host),
        command: "003",
        params: [nick],
        trailing:
          "This server was started #{:persistent_term.get(Sencha.Application.Started) |> DateTime.to_string()}"
      })
    )

    socket
    |> ThousandIsland.Socket.send(
      Sencha.Message.encode(%Sencha.Message{
        prefix: Application.fetch_env!(:sencha, :host),
        command: "004",
        params: [
          nick,
          Application.fetch_env!(:sencha, :host),
          "sencha-#{Application.spec(:sencha)[:vsn]}",
          "B",
          "b"
        ]
      })
    )

    socket
    |> ThousandIsland.Socket.send(
      Sencha.Message.encode(%Sencha.Message{
        prefix: Application.fetch_env!(:sencha, :host),
        command: "005",
        params: [nick, "MAXNICKLEN=#{Sencha.Repo.User.max_nickname_length()}"],
        trailing: "are supported by this server"
      })
    )

    send_motd({socket, state})

    :ok
  end

  def send_motd({socket, %Sencha.Handler.UserState{nickname: nick}}) do
    socket
    |> ThousandIsland.Socket.send(
      Sencha.Message.encode(%Sencha.Message{
        prefix: Application.fetch_env!(:sencha, :host),
        command: "422",
        params: [nick],
        trailing: "MOTD File is unimplemented"
      })
    )
  end
end
