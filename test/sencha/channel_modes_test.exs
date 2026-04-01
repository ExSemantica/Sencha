defmodule Sencha.Channel.Modes.Test do
  use ExUnit.Case, async: true

  setup do
    {:ok, modes: Sencha.Channel.Modes.defaults()}
  end

  test "successfully completes RFC 2812 channel MODE case 1", context do
    {:ok, {new, _errors}} = Sencha.Channel.Modes.parse(context.modes, ["+imI", "*!*@*.fi"])

    assert get_in(new, [?i])
    assert get_in(new, [?m])
    assert get_in(new, [?I]) |> MapSet.member?("*!*@*.fi")
  end

  test "successfully completes RFC 2812 channel MODE case 2", context do
    {:ok, {new, _errors}} = Sencha.Channel.Modes.parse(context.modes, ["+o", "Kilroy"])

    assert get_in(new, [?o]) |> MapSet.member?("Kilroy")
  end

  test "successfully completes RFC 2812 channel MODE case 3", context do
    {:ok, {new, _errors}} = Sencha.Channel.Modes.parse(context.modes, ["+v", "Wiz"])

    assert get_in(new, [?v]) |> MapSet.member?("Wiz")
  end

  test "successfully completes RFC 2812 channel MODE case 4", context do
    {:ok, {new, _errors}} = Sencha.Channel.Modes.parse(context.modes, ["-s"])

    assert not get_in(new, [?s])
  end

  test "successfully completes RFC 2812 channel MODE cases 5 and 6", context do
    {:ok, {new, _errors}} = Sencha.Channel.Modes.parse(context.modes, ["+k", "oulu"])
    assert get_in(new, [?k]) == "oulu"

    {:ok, {new, _errors}} = Sencha.Channel.Modes.parse(context.modes, ["-k", "oulu"])
    assert get_in(new, [?k]) == ""
  end

  test "successfully completes RFC 2812 channel MODE case 7", context do
    {:ok, {new, _errors}} = Sencha.Channel.Modes.parse(context.modes, ["+l", "10"])

    assert get_in(new, [?l]) == 10
  end

  test "successfully completes RFC 2812 channel MODE case 9", context do
    {:ok, {new, _errors}} = Sencha.Channel.Modes.parse(context.modes, ["+b", "*!*@*"])

    assert get_in(new, [?b]) |> MapSet.member?("*!*@*")
  end

  test "successfully completes RFC 2812 channel MODE case 11", context do
    {:ok, {new, _errors}} =
      Sencha.Channel.Modes.parse(context.modes, ["+be", "*!*@*.edu", "*!*@*.bu.edu"])

    assert get_in(new, [?b]) |> MapSet.member?("*!*@*.edu")
    assert get_in(new, [?e]) |> MapSet.member?("*!*@*.bu.edu")
  end
end
