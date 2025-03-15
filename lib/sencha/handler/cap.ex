defmodule Sencha.Handler.Cap do
  @moduledoc """
  Handles CAP capability passing in IRC.
  """
  @supported_capabilities MapSet.new(["sasl"])

  # Some other IRC clients do NOT comply with the CAP IRCv3 doc, let's fix that...
  def handle(
        %Sencha.Message{command: "CAP", params: ["REQ" | noncompliant], trailing: nil},
        {socket, state}
      ) do
    handle(
      %Sencha.Message{command: "CAP", params: ["REQ"], trailing: noncompliant |> Enum.join(" ")},
      {socket, state}
    )
  end

  def handle(
        %Sencha.Message{command: "CAP", params: ["LS" | _]},
        {socket, state = %Sencha.Handler.UserState{requested_handle: handle}}
      ) do
    # The official client only needs to support legacy CAP LS calls
    # Treat the IRC connections the same way
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

    {:cont, {socket, state}}
  end

  def handle(
        %Sencha.Message{command: "CAP", params: ["REQ"], trailing: caps_sent},
        {socket, state = %Sencha.Handler.UserState{requested_handle: handle, capabilities: old}}
      ) do
    new = caps_sent |> String.split(" ")

    # Disable these IRCv3 extensions
    disabled =
      new
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

    supported =
      capabilities
      |> MapSet.intersection(@supported_capabilities)

    nick = handle || "*"

    if supported == old do
      # No capabilities got changed
      socket
      |> ThousandIsland.Socket.send(
        %Sencha.Message{
          prefix: Sencha.ApplicationInfo.get_chat_hostname(),
          command: "CAP",
          params: [nick, "NAK"],
          trailing: capabilities
        }
        |> Sencha.Message.encode()
      )

      {:cont, {socket, state}}
    else
      # Capabilities were changed
      socket
      |> ThousandIsland.Socket.send(
        %Sencha.Message{
          prefix: Sencha.ApplicationInfo.get_chat_hostname(),
          command: "CAP",
          params: [nick, "ACK"],
          trailing: supported |> Enum.join(" ")
        }
        |> Sencha.Message.encode()
      )

      {:cont,
       {socket,
        %Sencha.Handler.UserState{state | capabilities: supported, capabilities_ok?: true}}}
    end
  end

  def handle(
        %Sencha.Message{command: "CAP", params: ["END"]},
        {socket, state = %Sencha.Handler.UserState{capabilities_ok?: true}}
      ) do
    if state.irc_state == :wait_for_cap_end do
      Sencha.Handler.try_authorize(socket.socket, state.requested_handle)
    end

    {:cont, {socket, state}}
  end

  def handle(
        %Sencha.Message{command: "CAP", params: [invalid | _]},
        {socket, state = %Sencha.Handler.UserState{requested_handle: handle}}
      ) do
    nick = handle || "*"

    socket
    |> ThousandIsland.Socket.send(
      %Sencha.Message{
        prefix: Sencha.ApplicationInfo.get_chat_hostname(),
        command: "410",
        params: [nick, invalid],
        trailing: "Invalid CAP command"
      }
      |> Sencha.Message.encode()
    )

    {:cont, {socket, state}}
  end
end
