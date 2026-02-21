defmodule Sencha.Channel.Modes do
  @moduledoc """
  Conveniences for handling channel modes.
  """

  @doc """
  Lists supported channel modes.
  """
  def supported(), do: MapSet.new([?b])

  @doc """
  Convenience for formatting modes
  """
  def format(modes), do: modes |> MapSet.to_list() |> to_string()

  @doc """
  Grant these upon creation
  """
  def defaults(), do: MapSet.new([])
end
