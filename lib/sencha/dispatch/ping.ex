defmodule Sencha.Dispatch.Ping do
  def handle(%Sencha.Message{params: [param]}, pid, _state) do
    Sencha.TCP.Client.transmit(pid, %Sencha.Message{command: "PONG", params: [param]})

    :ok
  end

  def handle(_message, _pid, _state), do: :ok
end
