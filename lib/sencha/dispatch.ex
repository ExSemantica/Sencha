defmodule Sencha.Dispatch do
  @moduledoc """
  Dispatch parsed inbound IRC commands to their appropriate modules.
  """
  def handle_command(message = %Sencha.Message{command: "NICK"}, client, state) do
    __MODULE__.Nick.handle(message, client, state)
  end

  def handle_command(message = %Sencha.Message{command: "PING"}, client, state) do
    __MODULE__.Ping.handle(message, client, state)
  end

  def handle_command(_message, _client, _state) do
    :ok
  end
end
