defmodule Sencha.Channel.Topic do
  @moduledoc """
  Conveniences for handling the topic of a `Sencha.Channel`.
  """

  @doc """
  Send the topic to a user given a `Sencha.Channel.State` and the user's
  `Sencha.User.State`.
  """
  def send(channel = %Sencha.Channel.State{}, ustate = %Sencha.User.State{})
      when channel.topic == "" do
    Sencha.Handler.send_message(ustate.handler_process, %Sencha.Message{
      prefix: Application.fetch_env!(:sencha, :host),
      command: "331",
      params: [ustate.nickname, channel.name],
      trailing: "No topic is set"
    })
  end

  def send(channel = %Sencha.Channel.State{}, ustate = %Sencha.User.State{}) do
    Sencha.Handler.send_message(ustate.handler_process, %Sencha.Message{
      prefix: Application.fetch_env!(:sencha, :host),
      command: "332",
      params: [ustate.nickname, channel.name],
      trailing: channel.topic
    })

    Sencha.Handler.send_message(ustate.handler_process, %Sencha.Message{
      prefix: Application.fetch_env!(:sencha, :host),
      command: "333",
      params: [
        ustate.nickname,
        channel.name,
        channel.topic_set_by,
        channel.topic_set |> DateTime.to_unix() |> to_string
      ],
      trailing: channel.topic
    })
  end
end
