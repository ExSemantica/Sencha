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

  - `tags`: The client sends these tags
  - `s_tags`: The server sends these tags, considered separate length from `tags`
  - `prefix`: The IRC target
  - `command`: The IRC command
  - `middle`: The IRC parameters
  - `traiing`: The IRC trailng parameters
  """
  @enforce_keys [:command]
  defstruct [:tags, :s_tags, :prefix, :command, :middle, :trailing]

  @max_params 14
  @max_bytes_tags 4095
  @max_bytes 511

  defguardp nospcrlfcl(c)
            when c in 0x01..0x09 or c in 0x0B..0x0C or c in 0x0E..0x1F or
                   c in 0x21..0x39 or c in 0x3B..0xFF

  defguardp trailing(c)
            when nospcrlfcl(c) or c == ?: or c == 0x20

  defguardp check_length_params(params) when length(params) <= @max_params
  defguardp check_length_tags(bytes) when byte_size(bytes) <= @max_bytes_tags
  defguardp check_length(bytes) when byte_size(bytes) <= @max_bytes

  defp parse_prefix(struct = %__MODULE__{}, ":" <> prefix) do
    %__MODULE__{struct | prefix: prefix}
  end

  defp parse_tail_stage2(struct = %__MODULE__{}, nil, params) do
    %__MODULE__{struct | middle: params |> Enum.reject(&(&1 == "")) |> Enum.reverse()}
  end

  defp parse_tail_stage2(struct = %__MODULE__{}, trailing, params) do
    %__MODULE__{
      struct
      | trailing: trailing |> check_trailing,
        middle: params |> Enum.reject(&(&1 == "")) |> Enum.reverse()
    }
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

  defp parse_stage0(message) do
    has_prefix? = message |> String.first() == ":"

    if has_prefix? do
      [prefix, tail] = String.split(message, " ", parts: 2)
      [t0 | t1] = String.split(tail, " ", parts: 2)

      %__MODULE__{command: t0, middle: []} |> parse_prefix(prefix) |> parse_tail(t1)
    else
      [t0 | t1] = String.split(message, " ", parts: 2)
      %__MODULE__{command: t0, middle: []} |> parse_tail(t1)
    end
  end

  defp parse_tags(tags) when byte_size(tags) > 0 do
    tags |> String.split(";") |> Enum.map(&parse_one_tag/1) |> Map.new()
  end

  defp parse_tags(_), do: nil

  # Cleaner way of nesting function bodies
  defp parse_one_tag_escaping(?\\, {:noescape, acc}), do: {:escape, acc}
  defp parse_one_tag_escaping(?:, {:escape, acc}), do: {:noescape, [?; | acc]}
  defp parse_one_tag_escaping(?s, {:escape, acc}), do: {:noescape, [0x20 | acc]}
  defp parse_one_tag_escaping(?\\, {:escape, acc}), do: {:noescape, [?\\ | acc]}
  defp parse_one_tag_escaping(?r, {:escape, acc}), do: {:noescape, [?\r | acc]}
  defp parse_one_tag_escaping(?n, {:escape, acc}), do: {:noescape, [?\n | acc]}
  defp parse_one_tag_escaping(e, {_cmd, acc}), do: {:noescape, [e | acc]}

  defp parse_one_tag(tag) do
    case String.split(tag, "=", parts: 2) do
      [t0, t1] ->
        {_cmd, t1_reduced} =
          t1
          |> to_charlist()
          |> Enum.reduce(
            {:noescape, []},
            &parse_one_tag_escaping/2
          )

        {t0,
         t1_reduced
         |> Enum.reverse()
         |> to_string}

      [t0] ->
        {t0, ""}
    end
  end

  @doc """
  Decodes a byte string into a structure representing an IRCv3 command
  """
  def decode(bytes) do
    has_tags? = bytes |> String.first() == "@"

    {tags, message} =
      if has_tags? do
        ["@" <> tags, message] = String.split(bytes, " ", parts: 2)
        {tags, message}
      else
        {"", bytes}
      end

    cond do
      check_length_tags(tags) and check_length(message) ->
        # IRCv3 tags and message are sane
        valid = %__MODULE__{} = parse_stage0(message)
        {:ok, %__MODULE__{valid | tags: parse_tags(tags)}}

      check_length(message) ->
        # IRCv3 tags are not sane, message is sane
        {:error, :too_many_tags}

      true ->
        # Message is not sane
        {:error, :too_long}
    end
  end

  defp sanitize_tag(tag) do
    tag
    |> to_charlist()
    |> Enum.map(fn c ->
      case c do
        ?; -> "\\:"
        0x20 -> "\\s"
        ?\\ -> "\\\\"
        ?\r -> "\\r"
        ?\n -> "\\n"
        _ -> c
      end
    end)
    |> List.flatten()
    |> to_string()
  end

  defp inject_one_tag({k, v}) when is_nil(v) or v == "", do: k
  defp inject_one_tag({k, v}), do: k <> "=" <> sanitize_tag(v)

  defp concatenate_tags(nil), do: ""

  defp concatenate_tags(tags) do
    tags
    |> Map.to_list()
    |> Enum.map_join(";", &inject_one_tag/1)
  end

  defp check_tags_final(final, "", ""), do: {:ok, final}

  defp check_tags_final(final, tags, "") when check_length_tags(tags),
    do: {:ok, "@" <> tags <> " " <> final}

  defp check_tags_final(final, "", s_tags) when check_length_tags(s_tags),
    do: {:ok, "@" <> s_tags <> " " <> final}

  defp check_tags_final(final, tags, s_tags)
       when check_length_tags(tags) and check_length_tags(s_tags),
       do: {:ok, "@" <> tags <> ";" <> s_tags <> " " <> final}

  defp check_tags_final(_final, _tags, _s_tags), do: {:error, :too_many_tags}

  defp inject_tags(final, tags, s_tags) when check_length(final) do
    tags_pre = concatenate_tags(tags)
    s_tags_pre = concatenate_tags(s_tags)

    final |> check_tags_final(tags_pre, s_tags_pre)
  end

  defp inject_tags(_final, _tags, _s_tags), do: {:error, :too_long}

  defp inject_parameters(nil, command, params) when is_nil(params) or params == [] do
    [command]
  end

  defp inject_parameters(nil, command, params) do
    [command, params]
  end

  defp inject_parameters(prefix, command, params) when is_nil(params) or params == [] do
    [":" <> prefix, command]
  end

  defp inject_parameters(prefix, command, params) do
    [":" <> prefix, command, params]
  end

  defp inject_trailing(list, nil) do
    list
  end

  defp inject_trailing(list, trailing) do
    [list, ":" <> trailing]
  end

  @doc """
  Encodes the structure into one IRCv3 packet, no CRLF
  """
  def encode(%__MODULE__{
        tags: tags,
        s_tags: s_tags,
        prefix: prefix,
        command: command,
        middle: middle,
        trailing: trailing
      }) do
    inject_parameters(prefix, command, middle)
    |> inject_trailing(trailing)
    |> List.flatten()
    |> Enum.join(" ")
    |> inject_tags(tags, s_tags)
  end
end
