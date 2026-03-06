defmodule Sencha.Channel.Modes do
  @moduledoc """
  Conveniences for parsing channel modes.
  """

  @magic_moderated? 1
  @magic_topic_locked? 2
  @magic_invite_only? 4
  @magic_secret? 8
  @magic_no_external? 16

  @doc """
  Lists supported channel modes.
  """
  defguard supported() when [?b, ?e, ?O, ?o, ?V, ?v, ?l, ?m, ?t, ?I, ?i, ?s, ?k, ?L, ?n]

  @doc """
  Lists chanop grantable (/MODE) channel modes.
  """
  defguard grantable() when [?b, ?e, ?O, ?o, ?V, ?v, ?l, ?m, ?t, ?I, ?i, ?s, ?k, ?n]

  @doc """
  Lists supported channel modes without parameters
  """
  defguard supported_non_parameters() when [?m, ?t, ?i, ?s, ?n]

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
  defguard supported_string_parameters() when [?k, ?L]

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
      ?b => MapSet.new(),
      ?e => MapSet.new(),
      ?O => MapSet.new(),
      ?o => MapSet.new(),
      ?V => MapSet.new(),
      ?v => MapSet.new(),
      ?I => MapSet.new(),
      ?l => 0,
      ?m => false,
      ?t => true,
      ?i => false,
      ?s => true,
      ?k => "",
      ?L => "",
      ?n => true
    }
  end

  @doc """
  Parse a set of modes such as from the tail of a `Sencha.Message`.
  """
  def parse([modes | modeparams], privileged? \\ false) do
    # EXAMPLE: -bbb test test2 test3
    # EXAMPLE: +bbbl test test2 test3 1337
    modes = modes |> to_charlist()

    case modes do
      [?+ | modes_added] ->
        {:ok, parse_one(%{}, modes_added, modeparams, :add, privileged?, %{})}

      [?- | modes_removed] ->
        {:ok, parse_one(%{}, modes_removed, modeparams, :remove, privileged?, %{})}

      _ ->
        :error
    end
  end

  @doc """
  Unparses a mode map into an iolist for a 'RPL_CHANNELMODEIS' 324 numeric.
  """
  def unparse(
        modemap = %{
          ?l => users_limit,
          ?m => moderated?,
          ?t => topic_locked?,
          ?i => invite_only?,
          ?s => secret?,
          ?n => no_external?
        }
      ) do
    {mchars, mparams} =
      modemap
      |> Map.keys()
      |> Enum.sort()
      |> Enum.reduce({[], []}, fn mchar, {mchars, mparams} ->
        case mchar do
          ?l when users_limit > 0 -> {[?l | mchars], [users_limit |> to_string | mparams]}
          ?m when moderated? -> {[?m | mchars], mparams}
          ?t when topic_locked? -> {[?t | mchars], mparams}
          ?i when invite_only? -> {[?i | mchars], mparams}
          ?s when secret? -> {[?s | mchars], mparams}
          ?n when no_external? -> {[?n | mchars], mparams}
          _ -> {mchars, mparams}
        end
      end)

    mchars = mchars |> Enum.reverse()
    mparams = mparams |> Enum.reverse()

    [mchars |> to_string | mparams]
  end

  @doc """
  Updates a regular mode map into a `Sencha.Repo.Channel`
  """
  def update(channel = %Sencha.Repo.Channel{}, %{
        ?b => bans,
        ?e => ban_exceptions,
        ?O => auto_ops,
        ?V => auto_voices,
        ?k => key,
        ?I => invites,
        ?l => users_limit,
        ?m => moderated?,
        ?t => topic_locked?,
        ?i => invite_only?,
        ?s => secret?,
        ?L => locked_reason,
        ?n => no_external?
      }) do
    # Have some bit-level math
    # The && is the true path
    # The || is the false path
    mask = 0
    mask = Bitwise.bor(mask, (moderated? && @magic_moderated?) || 0)
    mask = Bitwise.bor(mask, (topic_locked? && @magic_topic_locked?) || 0)
    mask = Bitwise.bor(mask, (invite_only? && @magic_invite_only?) || 0)
    mask = Bitwise.bor(mask, (secret? && @magic_secret?) || 0)
    mask = Bitwise.bor(mask, (no_external? && @magic_no_external?) || 0)
    # Define an endianness type so we don't mix up bits
    mask_bits = <<mask::integer-size(64)-little>>

    %Sencha.Repo.Channel{
      channel
      | bans: bans |> MapSet.to_list(),
        ban_exceptions: ban_exceptions |> MapSet.to_list(),
        operators: auto_ops |> MapSet.to_list(),
        voices: auto_voices |> MapSet.to_list(),
        invitation_masks: invites |> MapSet.to_list(),
        limit: users_limit,
        key: key,
        locked_reason: locked_reason,
        other_modes: mask_bits
    }
  end

  @doc """
  Convert a `Sencha.Repo.Channel` into a mode map
  """
  def to_modemap(%Sencha.Repo.Channel{
        key: key,
        locked_reason: locked_reason,
        limit: users_limit,
        bans: bans,
        ban_exceptions: ban_exceptions,
        operators: auto_ops,
        voices: auto_voices,
        invitation_masks: invites,
        other_modes: mask_bits
      }) do
    <<mask::integer-size(64)-little>> = mask_bits
    moderated? = Bitwise.band(mask, @magic_moderated?) != 0
    topic_locked? = Bitwise.band(mask, @magic_topic_locked?) != 0
    invite_only? = Bitwise.band(mask, @magic_invite_only?) != 0
    secret? = Bitwise.band(mask, @magic_secret?) != 0
    no_external? = Bitwise.band(mask, @magic_no_external?) != 0

    %{
      ?b => MapSet.new(bans),
      ?e => MapSet.new(ban_exceptions),
      ?O => MapSet.new(auto_ops),
      ?V => MapSet.new(auto_voices),
      ?I => MapSet.new(invites),
      ?v => MapSet.new(),
      ?o => MapSet.new(),
      ?k => key,
      ?l => users_limit,
      ?m => moderated?,
      ?t => topic_locked?,
      ?i => invite_only?,
      ?s => secret?,
      ?L => locked_reason,
      ?n => no_external?
    }
  end

  # ===========================================================================

  defp parse_one(modemap, [], [], _selection, _privileged?, errormap), do: {modemap, errormap}

  defp parse_one(modemap, [?k | modes_left], [key | modeparams], :add, false, errormap) do
    case modemap[?k] do
      "" ->
        parse_one(put_in(modemap, [?k], key), modes_left, modeparams, :add, false, errormap)

      current_key when current_key == key ->
        parse_one(put_in(modemap, [?k], key), modes_left, modeparams, :add, false, errormap)

      _ ->
        parse_one(
          modemap,
          modes_left,
          modeparams,
          :add,
          false,
          put_in(errormap, [?k], :incorrect_key)
        )
    end
  end

  defp parse_one(modemap, [?k | modes_left], [key | modeparams], :remove, false, errormap) do
    if key == modemap[?k] do
      parse_one(put_in(modemap, [?k], ""), modes_left, modeparams, :remove, false, errormap)
    else
      parse_one(
        modemap,
        modes_left,
        modeparams,
        :remove,
        false,
        put_in(errormap, [?k], :incorrect_key)
      )
    end
  end

  # IRC operator privilege short circuit
  defp parse_one(modemap, [?k | modes_left], [key | modeparams], :add, true, errormap) do
    parse_one(put_in(modemap, [?k], key), modes_left, modeparams, :add, true, errormap)
  end

  defp parse_one(modemap, [?k | modes_left], [_key | modeparams], :remove, true, errormap) do
    parse_one(put_in(modemap, [?k], ""), modes_left, modeparams, :remove, true, errormap)
  end

  # Regular users can not modify channel lockout
  defp parse_one(
         modemap,
         [?L | modes_left],
         [_lock_reason | modeparams],
         selection,
         false,
         errormap
       ) do
    parse_one(
      modemap,
      modes_left,
      modeparams,
      selection,
      false,
      put_in(errormap, [?L], :unprivileged)
    )
  end

  # IRC operators can, however
  defp parse_one(modemap, [?L | modes_left], [lock_reason | modeparams], :add, true, errormap) do
    parse_one(put_in(modemap, [?L], lock_reason), modes_left, modeparams, :add, true, errormap)
  end

  defp parse_one(modemap, [?L | modes_left], [_lock_reason | modeparams], :remove, true, errormap) do
    parse_one(put_in(modemap, [?L], ""), modes_left, modeparams, :remove, true, errormap)
  end

  defp parse_one(modemap, [mode | modes_left], modeparams, :add, privileged?, errormap) do
    cond do
      mode in supported_non_parameters() ->
        parse_one(
          put_in(modemap, [mode], true),
          modes_left,
          modeparams,
          :add,
          privileged?,
          errormap
        )

      mode in supported_integer_parameters() and modeparams != [] ->
        [param | modeparams] = modeparams
        {integer, _} = Integer.parse(param)

        parse_one(
          put_in(modemap, [mode], integer),
          modes_left,
          modeparams,
          :add,
          privileged?,
          errormap
        )

      mode in supported_string_parameters() and modeparams != [] ->
        [param | modeparams] = modeparams

        parse_one(
          put_in(modemap, [mode], param),
          modes_left,
          modeparams,
          :add,
          privileged?,
          errormap
        )

      mode in supported_mapset_parameters() and modeparams != [] ->
        [param | modeparams] = modeparams

        old = get_in(modemap, [mode])
        new = MapSet.put(old, param)

        parse_one(
          put_in(modemap, [mode], new),
          modes_left,
          modeparams,
          :add,
          privileged?,
          errormap
        )

      true ->
        parse_one(
          modemap,
          modes_left,
          modeparams,
          :add,
          privileged?,
          put_in(errormap, [mode], :unsupported)
        )
    end
  end

  defp parse_one(modemap, [mode | modes_left], modeparams, :remove, privileged?, errormap) do
    cond do
      mode in supported_non_parameters() ->
        parse_one(
          put_in(modemap, [mode], false),
          modes_left,
          modeparams,
          :remove,
          privileged?,
          errormap
        )

      mode in supported_integer_parameters() ->
        parse_one(
          put_in(modemap, [mode], 0),
          modes_left,
          modeparams,
          :remove,
          privileged?,
          errormap
        )

      mode in supported_string_parameters() ->
        parse_one(
          put_in(modemap, [mode], ""),
          modes_left,
          modeparams,
          :remove,
          privileged?,
          errormap
        )

      mode in supported_mapset_parameters() and modeparams != [] ->
        [param | modeparams] = modeparams

        old = get_in(modemap, [mode])
        new = MapSet.delete(old, param)

        parse_one(
          put_in(modemap, [mode], new),
          modes_left,
          modeparams,
          :remove,
          privileged?,
          errormap
        )

      true ->
        parse_one(
          modemap,
          modes_left,
          modeparams,
          :remove,
          privileged?,
          put_in(errormap, [mode], :unsupported)
        )
    end
  end
end
