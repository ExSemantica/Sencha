defmodule Sencha.User.Modes do
  @moduledoc """
  Conveniences for handling user modes.
  """

  @doc """
  Lists supported user modes.
  """
  defguard supported() when [?o, ?r, ?w]

  @doc """
  Lists grantable (/MODE) user modes.
  """
  defguard grantable() when [?w]

  @doc """
  Convenience for formatting modes
  """
  def format(modes), do: modes |> MapSet.to_list() |> to_string()

  @doc """
  Convenience for formatting supported modes
  """
  def format_supported(), do: supported() |> to_string()

  @doc """
  Grant these upon connection
  """
  def defaults(), do: MapSet.new([?r, ?w])

  @doc """
  Remove what isn't a grantable mode
  """
  def get_grantables(modes),
    do: MapSet.intersection(MapSet.new(modes), MapSet.new(grantable()))

  @doc """
  Remove what is an existant mode
  """
  def get_nonexistants(modes),
    do: MapSet.difference(MapSet.new(modes), MapSet.new(supported()))

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
