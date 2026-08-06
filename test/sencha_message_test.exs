# Sencha.Message test
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
defmodule SenchaTest.Message do
  require Logger
  use ExUnit.Case
  doctest Sencha.Message

  defp inject_tags(struct, nil) do
    struct
  end

  defp inject_tags(struct = %Sencha.Message{}, tags) do
    %Sencha.Message{
      struct
      | tags:
          tags
          |> Map.new()
    }
  end

  test "encodes IRC messages from structures properly" do
    path = Path.join([File.cwd!(), "test", "support", "irctest", "msg-split.yaml"])
    {:ok, cases} = YamlElixir.read_from_file(path)

    for c <- cases["tests"] do
      {:ok, parsed} = Sencha.Message.decode(c["input"])

      assert parsed.prefix == (c["atoms"]["source"] || nil),
             "prefix #{parsed.prefix} expected to be #{c["atoms"]["source"]}"

      assert parsed.command == (c["atoms"]["verb"] || nil),
             "command #{parsed.command} expected to be #{c["atoms"]["verb"]}"

      assert parsed.tags == c["atoms"]["tags"]

      cond do
        is_nil(c["atoms"]["params"]) ->
          :ok

        is_nil(parsed.trailing) ->
          for {p0, p1} <- Enum.zip(parsed.middle, c["atoms"]["params"]) do
            assert p0 == p1, "parameter '#{p0}}' expected to be '#{p1}'"
          end

        true ->
          middle_trailing = [parsed.middle, parsed.trailing] |> List.flatten()

          for {p0, p1} <- Enum.zip(middle_trailing, c["atoms"]["params"]) do
            assert p0 == p1, "parameter '#{p0}}' expected to be '#{p1}'"
          end
      end
    end
  end

  test "decodes IRC messages from strings properly" do
    path = Path.join([File.cwd!(), "test", "support", "irctest", "msg-join.yaml"])
    {:ok, cases} = YamlElixir.read_from_file(path)

    for c <- cases["tests"] do
      Logger.debug("Running IRCv3 test: " <> String.downcase(c["desc"]))

      messages =
        if is_nil(c["atoms"]["params"]) do
          [
            %Sencha.Message{
              prefix: c["atoms"]["source"],
              command: c["atoms"]["verb"],
              middle: []
            }
          ]
        else
          [tsirf | tsal] = c["atoms"]["params"] |> Enum.reverse()

          first = tsal |> Enum.reverse()
          last = tsirf

          cond do
            last |> String.starts_with?(":") or last == "" ->
              [
                %Sencha.Message{
                  prefix: c["atoms"]["source"],
                  command: c["atoms"]["verb"],
                  middle: first,
                  trailing: last
                }
              ]

            last |> String.split(" ") |> length() == 1 ->
              [
                %Sencha.Message{
                  prefix: c["atoms"]["source"],
                  command: c["atoms"]["verb"],
                  middle: [first, last] |> List.flatten()
                },
                %Sencha.Message{
                  prefix: c["atoms"]["source"],
                  command: c["atoms"]["verb"],
                  middle: first,
                  trailing: last
                }
              ]

            true ->
              [
                %Sencha.Message{
                  prefix: c["atoms"]["source"],
                  command: c["atoms"]["verb"],
                  middle: first,
                  trailing: last
                }
              ]
          end
        end
        |> Enum.map(&inject_tags(&1, c["atoms"]["tags"]))
        |> Enum.map(&Sencha.Message.encode/1)

      for m0 <- messages do
        {:ok, m1} = m0
        assert m1 in c["matches"]
      end
    end
  end
end
