defmodule Sencha.User.Modes do
  @moduledoc """
  Conveniences for handling user modes.
  """

  @doc """
  Lists supported user modes.
  """
  def supported(), do: MapSet.new([?o, ?r, ?w])

  @doc """
  Convenience for formatting modes
  """
  def format(modes), do: modes |> MapSet.to_list() |> to_string()

  @doc """
  Grant these upon connection
  """
  def defaults(), do: MapSet.new([?r, ?w])

  @doc """
  Sends modes to this client
  """
  def send_to_client(
        _state = %Sencha.User.State{nickname: nickname, modes: user_modes, handler_process: pid}
      ) do
    Sencha.Handler.send_message(pid, %Sencha.Message{
      prefix: Application.fetch_env!(:sencha, :host),
      command: "221",
      params: [nickname, user_modes |> format()]
    })
  end
end
