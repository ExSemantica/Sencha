# Dispatch IRCv3 command CAP
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
defmodule Sencha.Dispatch.Cap do
  @moduledoc false
  def capabilities, do: %{"sencha/test" => nil}

  # ===========================================================================
  # CAP LS
  # ===========================================================================
  def handle(
        state = %Sencha.User{target: target, capabilities: caps},
        _message = %Sencha.Message{middle: ["LS" | version]}
      ) do
    got =
      capabilities()
      |> Map.to_list()
      |> Enum.map_join(" ", fn {k, v} ->
        if is_nil(k) do
          k
        else
          "#{k}=#{v}"
        end
      end)

    case version do
      ["302"] ->
        Sencha.User.message_send(
          self(),
          %Sencha.Message{
            prefix: Application.fetch_env!(:sencha, :hostname),
            command: "CAP",
            middle: [target[:nickname] || "*", "LS"],
            trailing: got
          }
        )

      [] ->
        # Fallback
        Sencha.User.message_send(
          self(),
          %Sencha.Message{
            prefix: Application.fetch_env!(:sencha, :hostname),
            command: "CAP",
            middle: [target[:nickname] || "*", "LS"],
            trailing: got
          }
        )

      _ ->
        :ok
    end

    if caps == :wait_for_caps do
      %Sencha.User{state | capabilities: {:stall_for_caps, MapSet.new()}}
    else
      state
    end
  end

  # ===========================================================================
  # CAP LIST
  # ===========================================================================
  def handle(
        state = %Sencha.User{target: target, capabilities: {:ok, enabled}},
        _message = %Sencha.Message{middle: ["LIST"]}
      ) do
    # It doesn't need to be chunked since it's in the trailing parameter list
    Sencha.User.message_send(
      self(),
      %Sencha.Message{
        prefix: Application.fetch_env!(:sencha, :hostname),
        command: "CAP",
        middle: [target.nickname, "LIST"],
        trailing: enabled |> MapSet.to_list() |> Enum.join(" ")
      }
    )

    state
  end

  # ===========================================================================
  # CAP REQ
  # ===========================================================================
  def handle(
        state = %Sencha.User{target: target, capabilities: caps},
        message = %Sencha.Message{middle: ["REQ" | wanted]}
      ) do
    IO.inspect(state)
    IO.inspect(message)
    wanted_on = wanted |> Enum.reject(&String.starts_with?(&1, "-")) |> MapSet.new()

    wanted_off =
      wanted
      |> Enum.filter(&String.starts_with?(&1, "-"))
      |> Enum.map(&String.replace_prefix(&1, "-", ""))
      |> MapSet.new()

    had =
      case caps do
        {:ok, caps} -> caps
        {:stall_for_caps, caps} -> caps
        _ -> MapSet.new()
      end

    # sanitize stuff involving disabling and enabling the same CAP
    got = capabilities() |> Map.keys() |> MapSet.new()
    wanted_post = MapSet.difference(wanted_on, wanted_off)
    wanted_post = MapSet.union(wanted_post, had)
    yes = MapSet.intersection(got, wanted_post)
    no = MapSet.difference(got, wanted_post)

    chunks_rev =
      [yes |> MapSet.to_list(), wanted_off |> MapSet.to_list() |> Enum.map(&("-" <> &1))]
      |> List.flatten()
      |> Enum.chunk_every(11)
      |> Enum.reverse()

    chunks_rev_last = hd(chunks_rev)
    chunks_rev_others = tl(chunks_rev) |> Enum.reverse()

    if chunks_rev_others != [] do
      for chunk <- chunks_rev_others do
        Sencha.User.message_send(
          self(),
          %Sencha.Message{
            prefix: Application.fetch_env!(:sencha, :hostname),
            command: "CAP",
            middle:
              [
                target[:nickname] || "*",
                "ACK",
                "*",
                chunk
              ]
              |> List.flatten()
          }
        )
      end
    end

    Sencha.User.message_send(
      self(),
      %Sencha.Message{
        prefix: Application.fetch_env!(:sencha, :hostname),
        command: "CAP",
        middle:
          [
            target[:nickname] || "*",
            "ACK",
            chunks_rev_last
          ]
          |> List.flatten()
      }
    )

    if length(MapSet.to_list(no)) > 0 do
      chunks_rev =
        no
        |> MapSet.to_list()
        |> Enum.chunk_every(11)
        |> Enum.reverse()

      chunks_rev_last = hd(chunks_rev)
      chunks_rev_others = tl(chunks_rev) |> Enum.reverse()

      if chunks_rev_others != [] do
        for chunk <- chunks_rev_others do
          Sencha.User.message_send(
            self(),
            %Sencha.Message{
              prefix: Application.fetch_env!(:sencha, :hostname),
              command: "CAP",
              middle:
                [
                  target[:nickname] || "*",
                  "NAK",
                  "*",
                  chunk
                ]
                |> List.flatten()
            }
          )
        end
      end

      Sencha.User.message_send(
        self(),
        %Sencha.Message{
          prefix: Application.fetch_env!(:sencha, :hostname),
          command: "CAP",
          middle:
            [
              target[:nickname] || "*",
              "NAK",
              chunks_rev_last
            ]
            |> List.flatten()
        }
      )
    end

    %Sencha.User{state | capabilities: {:stall_for_caps, yes}}
  end

  # ===========================================================================
  # CAP END
  # ===========================================================================
  def handle(
        state = %Sencha.User{capabilities: {:stall_for_caps, caps}},
        _message = %Sencha.Message{middle: ["END"]}
      ) do
    %Sencha.User{state | capabilities: {:ok, caps}}
  end

  def handle(
        state,
        _message
      ) do
    state
  end
end
