defmodule Sencha.Channel.Modes do
  @moduledoc """
  Conveniences for handling channel modes.

  TODO: Finish this
  """

  @doc """
  Lists supported channel modes.
  """
  defguard supported() when [?b, ?e, ?O, ?o, ?V, ?v, ?l, ?m, ?t]

  @doc """
  Lists chanop grantable (/MODE) channel modes.
  """
  defguard grantable() when [?b, ?e, ?O, ?o, ?V, ?v, ?l, ?m, ?t]

  @doc """
  Lists supported channel modes without parameters
  """
  defguard supported_non_parameters() when [?m, ?t]

  @doc """
  Lists supported channel modes with MapSet parameters
  """
  defguard supported_mapset_parameters() when [?b, ?e, ?O, ?o, ?V, ?v]

  @doc """
  Lists supported channel modes with integer parameters
  """
  defguard supported_integer_parameters() when [?l]

  @doc """
  Lists supported channel modes with string parameters
  """
  defguard supported_string_parameters() when []

  def format_supported(), do: supported() |> to_string()

  def format_supported_parameters() do
    Enum.concat([
      supported_mapset_parameters(),
      supported_integer_parameters(),
      supported_string_parameters()
    ])
    |> to_string()
  end

  def format_supported_non_parameters(), do: supported_non_parameters() |> to_string()

  @doc """
  Set these upon creation
  """
  def defaults() do
    %{
      ?b => MapSet.new([]),
      ?e => MapSet.new([]),
      ?O => MapSet.new([]),
      ?o => MapSet.new([]),
      ?V => MapSet.new([]),
      ?v => MapSet.new([]),
      ?l => Sencha.Repo.Channel.default_channel_limit(),
      ?m => false,
      ?t => true
    }
  end

  def merge(old, deltas) do
    deltas |> Enum.reduce(old, &parse_delta/2)
  end

  defp parse_delta(delta, old) do
    split = String.split(delta, " ")

    split =
      case split do
        [a, b] -> [a |> to_charlist, b]
        [a] -> [a |> to_charlist]
      end
      |> List.flatten()
      |> Enum.filter(fn [_ | tail] ->
        hd(tail) in supported()
      end)

    case split do
      [?+, char, param] when char in supported_integer_parameters() ->
        {int, _} = Integer.parse(param)
        old |> put_in([char], int)

      [?+, char, param] when char in supported_string_parameters() ->
        old |> put_in([char], param)

      [?+, char] when char in supported_non_parameters() ->
        old |> put_in([char], true)

      [?+, char, param] when char in supported_mapset_parameters() ->
        old |> update_in([char], fn old_mode -> old_mode |> MapSet.put(param) end)

      [?-, char, param] when char in supported_mapset_parameters() ->
        old |> update_in([char], fn old_mode -> old_mode |> MapSet.delete(param) end)

      [?-, char] when char not in supported_mapset_parameters() ->
        old |> put_in([char], false)
    end
  end
end
