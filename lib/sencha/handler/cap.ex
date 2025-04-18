defmodule Sencha.Handler.Cap do
  @moduledoc """
  Handles CAP capability passing in IRC.
  """
  @supported_capabilities MapSet.new(["sasl"])

  # Some IRC clients do NOT comply with the CAP IRCv3 draft, let's fix that.
  def handle(pid, message = %Sencha.Message{params: ["REQ" | tail], trailing: nil}, socket) do
    handle(
      pid,
      %Sencha.Message{message | params: ["REQ"], trailing: tail |> Enum.join(" ")},
      socket
    )
  end

  def handle(pid, %Sencha.Message{params: ["LS" | _]}, socket) do
    {:ok, handle} = Sencha.Handler.get_username(pid)
    nick = handle || "*"

    socket
    |> ThousandIsland.Socket.send(
      %Sencha.Message{
        prefix: Sencha.ApplicationInfo.get_chat_hostname(),
        command: "CAP",
        params: [nick, "LS"],
        trailing: @supported_capabilities |> Enum.join(" ")
      }
      |> Sencha.Message.encode()
    )
  end

  def handle(pid, %Sencha.Message{params: ["REQ"], trailing: caps_sent}, socket) do
    {:ok, handle} = Sencha.Handler.get_username(pid)
    nick = handle || "*"

    {:ok, old} = Sencha.Handler.get_capabilities(pid)
    new = caps_sent |> String.split(" ")

    # Disable these IRCv3 extensions
    disabled =
      caps_sent
      |> Enum.filter(&(String.first(&1) == "-"))
      |> Enum.map(&String.replace_prefix(&1, "-", ""))
      |> MapSet.new()

    # Enable these ones and join them with the old set of IRCv3 extensions when 
    # initially enabled
    capabilities =
      new
      |> Enum.filter(&(String.first(&1) != "-"))
      |> MapSet.new()
      |> MapSet.union(old)
      |> MapSet.difference(disabled)
  end

  def handle(pid, %Sencha.Message{params: ["END"]}, _socket) do
    Sencha.Handler.on_end_capabilities(pid)
  end

  def handle(pid, %Sencha.Message{params: [invalid | _]}, _socket) do
    Sencha.Handler.on_invalid_capabilities(pid, invalid)
  end
end
