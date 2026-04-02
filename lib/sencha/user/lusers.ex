defmodule Sencha.User.Lusers do
  @moduledoc """
  Convenience for sending the MOTD.
  """
  def send_to_client(%Sencha.User.State{handler_process: handler, nickname: nick}) do
    servers = length([node() | Node.list()])
    local = Sencha.Scoreboard.accumulate(true)
    global = Sencha.Scoreboard.accumulate(true)
    channels = Sencha.Repo.aggregate(Sencha.Repo.Channel, :count)

    Sencha.Handler.send_message(handler, %Sencha.Message{
      prefix: Application.fetch_env!(:sencha, :host),
      command: "251",
      params: [nick],
      trailing: "There are #{global.total} users and #{global.invisible} on #{servers} servers"
    })

    Sencha.Handler.send_message(handler, %Sencha.Message{
      prefix: Application.fetch_env!(:sencha, :host),
      command: "252",
      params: [nick, to_string(local.operators)],
      trailing: "operator(s) online"
    })

    Sencha.Handler.send_message(handler, %Sencha.Message{
      prefix: Application.fetch_env!(:sencha, :host),
      command: "253",
      params: [nick, to_string(local.unknown)],
      trailing: "unknown connection(s)"
    })

    Sencha.Handler.send_message(handler, %Sencha.Message{
      prefix: Application.fetch_env!(:sencha, :host),
      command: "254",
      params: [nick, to_string(channels)],
      trailing: "channels formed"
    })

    Sencha.Handler.send_message(handler, %Sencha.Message{
      prefix: Application.fetch_env!(:sencha, :host),
      command: "255",
      params: [nick],
      trailing: "I have #{local.total} users and #{servers - 1} servers"
    })

    Sencha.Handler.send_message(handler, %Sencha.Message{
      prefix: Application.fetch_env!(:sencha, :host),
      command: "265",
      params: [nick, to_string(local.total), to_string(local.maximum)],
      trailing: "Current local users #{local.total}, max #{local.maximum}"
    })

    Sencha.Handler.send_message(handler, %Sencha.Message{
      prefix: Application.fetch_env!(:sencha, :host),
      command: "266",
      params: [nick, to_string(global.total), to_string(global.maximum)],
      trailing: "Current global users #{global.total}, max #{global.maximum}"
    })

    :ok
  end
end
