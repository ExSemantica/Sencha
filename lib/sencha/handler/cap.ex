defmodule Sencha.Handler.Cap do
  @moduledoc """
  Handles CAP capability passing in IRC.
  """
  @supported_capabilities MapSet.new(["sasl"])
  
  def get_supported(), do: @supported_capabilities

  # Some IRC clients do NOT comply with the CAP IRCv3 draft, let's fix that.
  def handle(pid, message = %Sencha.Message{params: ["REQ" | tail], trailing: nil}, socket) do
    handle(
      pid,
      %Sencha.Message{message | params: ["REQ"], trailing: tail |> Enum.join(" ")},
      socket
    )
  end

  def handle(pid, %Sencha.Message{params: ["LS" | _]}, _socket) do
    send(pid, :capabilities_info)
  end

  def handle(pid, %Sencha.Message{params: ["REQ"], trailing: caps_sent}, _socket) do
    send(pid, {:capabilities_set, caps_sent |> String.split(" ")})
  end

  def handle(pid, %Sencha.Message{params: ["END"]}, _socket) do
    send(pid, :capabilities_ok)
  end

  def handle(pid, %Sencha.Message{params: [invalid | _]}, _socket) do
    send(pid, {:capabilities_invalid, invalid})
  end
end
