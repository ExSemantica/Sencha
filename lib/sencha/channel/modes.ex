defmodule Sencha.Channel.Modes do
  @moduledoc """
  Conveniences for parsing channel modes.
  """

  @doc """
  Lists supported channel modes.
  """
  defguard supported() when [?b, ?e, ?O, ?o, ?V, ?v, ?l, ?m, ?t, ?I, ?i, ?s, ?k]

  @doc """
  Lists chanop grantable (/MODE) channel modes.
  """
  defguard grantable() when [?b, ?e, ?O, ?o, ?V, ?v, ?l, ?m, ?t, ?I, ?i, ?s, ?k]

  @doc """
  Lists supported channel modes without parameters
  """
  defguard supported_non_parameters() when [?m, ?t, ?i, ?s]

  @doc """
  Lists supported channel modes with MapSet parameters
  """
  defguard supported_mapset_parameters() when [?b, ?e, ?O, ?o, ?V, ?v, ?I]

  @doc """
  Lists supported channel modes with integer parameters
  """
  defguard supported_integer_parameters() when [?l]

  @doc """
  Lists supported channel modes with string parameters
  """
  defguard supported_string_parameters() when [?k]

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
      ?I => MapSet.new([]),
      ?l => 0,
      ?m => false,
      ?t => true,
      ?i => false,
      ?s => true,
      ?k => ""
    }
  end

  @doc """
  Given a mode map, try parsing a set of modes such as from the tail of a
  `Sencha.Message`.
  """
  def parse(modemap, [modes | modeparams]) do
    # EXAMPLE: -bbb test test2 test3
    # EXAMPLE: +bbbl test test2 test3 1337
    modes = modes |> to_charlist()

    case modes do
      [?+ | modes_added] ->
        {:ok, parse_one(modemap, modes_added, modeparams, :add)}

      [?- | modes_removed] ->
        {:ok, parse_one(modemap, modes_removed, modeparams, :remove)}

      _ ->
        :error
    end
  end

  defp parse_one(modemap, [], [], _selection), do: modemap

  defp parse_one(modemap, [?k | modes_left], [key | modeparams], :add) do
    case modemap[?k] do
      "" ->
        parse_one(put_in(modemap, [?k], key), modes_left, modeparams, :add)

      current_key when current_key == key ->
        parse_one(put_in(modemap, [?k], key), modes_left, modeparams, :add)

      _ ->
        parse_one(modemap, modes_left, modeparams, :add)
    end
  end

  defp parse_one(modemap, [?k | modes_left], [key | modeparams], :remove) do
    if key == modemap[?k] do
      parse_one(put_in(modemap, [?k], ""), modes_left, modeparams, :remove)
    else
      parse_one(modemap, modes_left, modeparams, :remove)
    end
  end

  defp parse_one(modemap, [mode | modes_left], modeparams, :add) do
    cond do
      mode in supported_non_parameters() ->
        parse_one(put_in(modemap, [mode], true), modes_left, modeparams, :add)

      mode in supported_integer_parameters() and modeparams != []  ->
        [param | modeparams] = modeparams
        {integer, _} = Integer.parse(param)

        parse_one(put_in(modemap, [mode], integer), modes_left, modeparams, :add)

      mode in supported_string_parameters() and modeparams != [] ->
        [param | modeparams] = modeparams

        parse_one(put_in(modemap, [mode], param), modes_left, modeparams, :add)

      mode in supported_mapset_parameters() and modeparams != [] ->
        [param | modeparams] = modeparams

        old = get_in(modemap, [mode])
        new = MapSet.put(old, param)

        parse_one(put_in(modemap, [mode], new), modes_left, modeparams, :add)

      true ->
        parse_one(modemap, modes_left, modeparams, :add)
    end
  end

  defp parse_one(modemap, [mode | modes_left], modeparams, :remove) do
    cond do
      mode in supported_non_parameters() ->
        parse_one(put_in(modemap, [mode], false), modes_left, modeparams, :remove)

      mode in supported_integer_parameters() ->
        parse_one(put_in(modemap, [mode], 0), modes_left, modeparams, :remove)

      mode in supported_string_parameters() ->
        parse_one(put_in(modemap, [mode], ""), modes_left, modeparams, :remove)

      mode in supported_mapset_parameters() and modeparams != [] ->
        [param | modeparams] = modeparams

        old = get_in(modemap, [mode])
        new = MapSet.delete(old, param)

        parse_one(put_in(modemap, [mode], new), modes_left, modeparams, :remove)

      true ->
        parse_one(modemap, modes_left, modeparams, :remove)
    end
  end
end
