defmodule Sencha.Commands.Authenticate do
  @moduledoc """
  Handle 'AUTHENTICATE' IRCv3 commands
  """
  def handle_irc(
        _pid,
        _packet,
        {socket, %Sencha.Handler.UserState{authentication_state: auth_state, nickname: nickname}}
      )
      when auth_state == :ok or auth_state == :waiting_for_capabilities do
    socket
    |> ThousandIsland.Socket.send(
      Sencha.Message.encode(%Sencha.Message{
        prefix: Application.fetch_env!(:sencha, :host),
        command: "907",
        params: [nickname],
        trailing: "You have already authenticated using SASL"
      })
    )

    :ok
  end

  def handle_irc(
        _pid,
        %Sencha.Message{params: ["PLAIN"]},
        {socket, %Sencha.Handler.UserState{authentication_state: :waiting_for_authentication}}
      ) do
    socket
    |> ThousandIsland.Socket.send(
      Sencha.Message.encode(%Sencha.Message{
        prefix: Application.fetch_env!(:sencha, :host),
        command: "AUTHENTICATE",
        params: ["+"]
      })
    )

    :ok
  end

  def handle_irc(
        pid,
        %Sencha.Message{params: [data]},
        {_socket, %Sencha.Handler.UserState{authentication_state: :waiting_for_authentication}}
      ) do
    :ok = Sencha.Handler.authentication_put(pid, data)

    :ok
  end

  def handle_irc(_pid, _packet, {_socket, _state}) do
    :ok
  end
end
