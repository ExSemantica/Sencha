defmodule Sencha.User.MOTD do
  @moduledoc """
  Convenience for sending the MOTD.
  """
  def send_to_client(%Sencha.User.State{handler_process: handler, nickname: nick}) do
    motd = :persistent_term.get(Sencha.MOTD, nil)

    case motd do
      nil ->
        Sencha.Handler.send_message(handler, %Sencha.Message{
          prefix: Application.fetch_env!(:sencha, :host),
          command: "422",
          params: [nick],
          trailing: "MOTD File is not available"
        })

      motd ->
        Sencha.Handler.send_message(handler, %Sencha.Message{
          prefix: Application.fetch_env!(:sencha, :host),
          command: "375",
          params: [nick],
          trailing: "-- Message of the Day --"
        })

        motd
        |> Enum.map(fn line ->
          Sencha.Handler.send_message(handler, %Sencha.Message{
            prefix: Application.fetch_env!(:sencha, :host),
            command: "375",
            params: [nick],
            trailing: line
          })
        end)

        Sencha.Handler.send_message(handler, %Sencha.Message{
          prefix: Application.fetch_env!(:sencha, :host),
          command: "376",
          params: [nick],
          trailing: "End of /MOTD command"
        })
    end

    :ok
  end
end
