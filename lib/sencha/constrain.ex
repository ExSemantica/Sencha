defmodule Sencha.Constrain do
  @moduledoc """
  Constraints for different variables. (nick, ident, channel, etc.)
  """
  @len_nick 15
  @len_channel 31
  @channel_prefixes [?#]

  def max_length_nick(), do: @len_nick
  def max_length_channel(), do: @len_channel

  def concat_channel_prefixes(), do: @channel_prefixes |> Enum.join()

  @doc """
  Checks if this nickname is syntactically valid.

  Note that the nickname might collide.
  """
  def valid_nick?(nick) do
    nick = nick |> to_charlist

    [nick_head | nick_tail] = nick

    cond do
      # is the nick too long?
      length(nick) > @len_nick ->
        false

      # note that RFC 2812 gives a separate requirement for first char of nick
      nick_head not in 0x41..0x5A and nick_head not in 0x61..0x7A ->
        false

      # now check for RFC 2812's rest of nick chars
      Enum.any?(
        nick_tail,
        &(&1 not in 0x41..0x5A and &1 not in 0x30..0x39 and &1 not in 0x61..0x7A and &1 != ?-)
      ) ->
        false

      true ->
        true
    end
  end

  @doc """
  Checks if this channel is syntactically valid. Checks the channel type too.

  Note that the channel might collide.
  """
  def valid_channel?(channel) do
    channel = channel |> to_charlist
    [channel_head | channel_tail] = channel

    cond do
      # is the channel too long?
      length(channel) > @len_channel ->
        false

      # Check if channel is a supported prefix.
      channel_head not in @channel_prefixes ->
        false

      # Support IRCv3 channel name restrictions
      # NOTE: We don't want to support non-ASCII wide chars in channels either
      Enum.any?(
        channel_tail,
        &(&1 == 0x20 or &1 == 0x07 or &1 == 0x2C or &1 > 0xFF)
      ) ->
        false

      true ->
        true
    end
  end
end
