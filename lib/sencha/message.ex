# RFC 2812 IRC message handling
# Copyright 2026 Roland Metivier
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
defmodule Sencha.Message do
  @moduledoc """
  RFC 2812 IRC message handling

  TODO: Should be tested
  """
  @enforce_keys [:command]
  defstruct [:prefix, :command, :middle, :trailing]

  @max_params 14
  @max_bytes 510

  defguardp nospcrlfcl(c)
            when c in 0x01..0x09 or c in 0x0B..0x0C or c in 0x0E..0x1F or
                   c in 0x21..0x39 or c in 0x3B..0xFF

  defguardp trailing(c)
            when nospcrlfcl(c) or c == ?: or c == 0x20

  defguardp letter(c) when c in 0x41..0x5A or c in 0x61..0x7A

  defguardp digit(c) when c in 0x30..0x39

  defguardp check_length_params(params) when length(params) <= @max_params
  defguardp check_length(bytes) when byte_size(bytes) <= @max_bytes

  defp parse_prefix(struct = %__MODULE__{}, ":" <> prefix) do
    decoded = %Sencha.Prefix{nickname: nickname, host: host} = Sencha.Prefix.decode(prefix)
    valid_host? = Sencha.check_hostname(host)
    valid_nickname? = if is_nil(nickname), do: true, else: Sencha.check_nickname(nickname)

    if valid_host? and valid_nickname? do
      %__MODULE__{struct | prefix: decoded}
    end
  end

  defp parse_prefix(_struct, _prefix) do
    {:error, :invalid}
  end

  defp parse_command(command) do
    valid_command? = command |> to_charlist |> Enum.all?(&letter/1)

    valid_numeric? = command |> to_charlist |> Enum.all?(&digit/1)
    valid_numeric? = valid_numeric? && byte_size(command) == 3

    command
    |> parse_command_stage1(valid_command?: valid_command?, valid_numeric?: valid_numeric?)
  end

  defp parse_command_stage1(command, valid_command?: false, valid_numeric?: true) do
    %__MODULE__{command: command}
  end

  defp parse_command_stage1(command, valid_command?: true, valid_numeric?: false) do
    %__MODULE__{command: command}
  end

  defp parse_command_stage1(_command, _invalid) do
    {:error, :invalid}
  end

  defp parse_tail_stage2(struct = %__MODULE__{}, nil, params) do
    %__MODULE__{struct | middle: params |> Enum.reverse()}
  end

  defp parse_tail_stage2(struct = %__MODULE__{}, trailing, params) do
    %__MODULE__{struct | trailing: trailing |> check_trailing, middle: params |> Enum.reverse()}
  end

  defp check_param(param) do
    valid? = param |> to_charlist |> Enum.all?(&nospcrlfcl/1)

    if valid? do
      param
    end
  end

  defp check_trailing(trail) do
    valid? = trail |> to_charlist |> Enum.all?(&trailing/1)

    if valid? do
      trail
    end
  end

  defp parse_tail_stage1(struct, tail, params) when check_length_params(params) do
    has_trailing? = tail |> String.first() == ":"

    cond do
      has_trailing? ->
        ":" <> trailing = tail

        struct
        |> parse_tail_stage2(trailing, params)

      tail == "" ->
        struct
        |> parse_tail_stage2(nil, params)

      true ->
        case tail |> String.split(" ", parts: 2) do
          [s0] ->
            struct
            |> parse_tail_stage2(nil, [s0 |> check_param() | params])

          [s0, s1] ->
            struct
            |> parse_tail_stage1(s1, [s0 |> check_param() | params])
        end
    end
  end

  defp parse_tail_stage1(_struct, _tail, params) when params != [] do
    {:error, :too_many_parameters}
  end

  defp parse_tail(struct = %__MODULE__{}, []) do
    struct
  end

  defp parse_tail(struct = %__MODULE__{}, [tail]) do
    struct
    |> parse_tail_stage1(tail, [])
  end

  defp parse_tail(error = {:error, _what}, _type) do
    error
  end

  def decode(bytes) when check_length(bytes) do
    has_prefix? = bytes |> String.first() == ":"

    if has_prefix? do
      [prefix, tail] = String.split(bytes, " ", parts: 2)
      [t0 | t1] = String.split(tail, " ", parts: 2)

      parse_command(t0) |> parse_prefix(prefix) |> parse_tail(t1)
    else
      [t0 | t1] = String.split(bytes, " ", parts: 2)
      parse_command(t0) |> parse_tail(t1)
    end
  end

  def encode(%__MODULE__{prefix: nil, command: command, middle: middle, trailing: nil}) do
    [command, middle] |> List.flatten() |> Enum.join(" ")
  end
  def encode(%__MODULE__{prefix: nil, command: command, middle: middle, trailing: trailing}) do
    [command, middle, ":" <> trailing] |> List.flatten() |> Enum.join(" ")
  end
  def encode(%__MODULE__{prefix: prefix, command: command, middle: middle, trailing: nil}) do
    [":" <> (prefix |> Sencha.Prefix.encode()), command, middle]
    |> List.flatten()
    |> Enum.join(" ")
  end
  def encode(%__MODULE__{prefix: prefix, command: command, middle: middle, trailing: trailing}) do
    [":" <> (prefix |> Sencha.Prefix.encode()), command, middle, ":" <> trailing]
    |> List.flatten()
    |> Enum.join(" ")
  end
end
