defmodule Sencha.Commands.Cap do
  @moduledoc """
  Handle 'CAP' IRCv3 commands
  """
  def handle_irc(
        pid,
        packet = %Sencha.Message{params: ["REQ" | rest], trailing: nil},
        {socket, state}
      ) do
    # Some shady IRC clients do not comply with the IRCv3 CAP draft
    [rest] = rest

    handle_irc(
      pid,
      %Sencha.Message{packet | params: ["REQ"], trailing: rest},
      {socket, state}
    )
  end

  def handle_irc(_pid, %Sencha.Message{params: ["LS" | _rest]}, {socket, state}) do
    # What nickname I currently have, or if nil default to '*'
    nickname = state.nickname || "*"

    socket
    |> ThousandIsland.Socket.send(
      Sencha.Message.encode(%Sencha.Message{
        prefix: Application.fetch_env!(:sencha, :host),
        command: "CAP",
        params: [nickname, "LS"],
        trailing:
          Sencha.Handler.Capabilities.supported()
          |> Enum.map_join(" ", &Sencha.Handler.Capabilities.format_long/1)
      })
    )

    :ok
  end

  def handle_irc(
        pid,
        %Sencha.Message{params: ["REQ"], trailing: delta},
        {_socket, _state}
      ) do
    :ok = Sencha.Handler.capabilities_request(pid, delta)

    :ok
  end

  def handle_irc(
        _pid,
        %Sencha.Message{params: ["LIST"]},
        {socket, state}
      ) do
    # What nickname do I currently have, or if nil default to '*'
    nickname = state.nickname || "*"

    socket
    |> ThousandIsland.Socket.send(
      Sencha.Message.encode(%Sencha.Message{
        prefix: Application.fetch_env!(:sencha, :host),
        command: "CAP",
        params: [nickname, "LIST"],
        trailing: state.capabilities
      })
    )

    :ok
  end

  def handle_irc(pid, %Sencha.Message{params: ["END"]}, {_socket, _state}) do
    :ok = Sencha.Handler.capabilities_end(pid)

    :ok
  end

  def handle_irc(_pid, _packet, {_socket, _state}) do
    :ok
  end
end
