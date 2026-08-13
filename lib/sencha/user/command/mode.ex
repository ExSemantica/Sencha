# Dispatch IRCv3 command MODE
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
defmodule Sencha.User.Command.Mode do
  @moduledoc false
  @modes_viewable_by_default [?n, ?t]

  def handle(
        state = %Sencha.User{target: target},
        socket,
        %Sencha.Message{middle: ["#" <> channel, modes_keys | modes_vals]}
      ) do
    channel_hash = String.downcase("#" <> channel)
    modes_keys = modes_keys |> to_charlist()

    modes_adjust =
      case hd(modes_keys) do
        ?+ -> :add
        ?- -> :del
        other -> {:view, other}
      end

    modes_keys = tl(modes_keys)

    :mnesia.transaction(fn ->
      case :mnesia.read(__MODULE__.Roster, channel_hash) do
        [
          {__MODULE__.Roster, ^channel_hash, targets, %Sencha.Channel{name: real_channel},
           %{?o => operators}}
        ] ->
          in_channel? = target in targets
          operator? = target in operators

          case modes_adjust do
            {:view, ?b} ->
              :unimplemented

            {:view, ?e} ->
              :unimplemented

            :add when in_channel? and operator? ->
              {_, mode_delta} =
                modes_keys
                |> Enum.map_reduce({%{}, modes_vals}, fn
                  k, {acc, vals} ->
                    have_param? =
                      ?a..?c
                      |> Enum.any?(fn t -> MapSet.member?(Sencha.Channel.modes(t), k) end)

                    no_param? = MapSet.member?(Sencha.Channel.modes(?d), k)

                    cond do
                      no_param? ->
                        {k, {acc |> put_in([k], nil), vals}}

                      have_param? ->
                        [v | vals] = vals
                        {k, {acc |> put_in([k], v), vals}}
                    end
                end)

              Sencha.Channel.update_modes_in_transaction(
                channel_hash,
                target,
                mode_delta,
                :add
              )

            :del when in_channel? and operator? ->
              {_, mode_delta} =
                modes_keys
                |> Enum.map_reduce({%{}, modes_vals}, fn
                  k, {acc, vals} ->
                    have_param? =
                      ?a..?b
                      |> Enum.any?(fn t -> MapSet.member?(Sencha.Channel.modes(t), k) end)

                    no_param? =
                      ?c..?d
                      |> Enum.any?(fn t -> MapSet.member?(Sencha.Channel.modes(t), k) end)

                    cond do
                      no_param? ->
                        {k, {acc |> pop_in([k]), vals}}

                      have_param? ->
                        [_ | vals] = vals
                        {k, {acc |> pop_in([k]), vals}}
                    end
                end)

              Sencha.Channel.update_modes_in_transaction(
                channel_hash,
                target,
                mode_delta,
                :del
              )

            _ when not in_channel? ->
              Sencha.User.message_send(
                socket,
                Sencha.User.Numeric.encode(:ERR_NOTONCHANNEL, target, %{
                  channel: real_channel
                }),
                target
              )

            _ when not operator? ->
              Sencha.User.message_send(
                socket,
                Sencha.User.Numeric.encode(:ERR_CHANOPPRIVSNEEDED, target, %{
                  channel: real_channel
                }),
                target
              )
          end

        [] ->
          Sencha.User.message_send(
            socket,
            Sencha.User.Numeric.encode(:ERR_NOSUCHCHANNEL, target, %{
              channel: "#" <> channel
            }),
            target
          )
      end
    end)

    state
  end

  def handle(
        state = %Sencha.User{target: target},
        socket,
        %Sencha.Message{middle: ["#" <> channel]}
      ) do
    channel_hash = String.downcase("#" <> channel)

    :mnesia.transaction(fn ->
      case :mnesia.read(Sencha.Channel.Roster, channel_hash) do
        [] ->
          # Nobody on this channel
          Sencha.User.message_send(
            socket,
            Sencha.User.Numeric.encode(:ERR_NOSUCHCHANNEL, target, %{
              channel: "#" <> channel
            }),
            target
          )

        [
          {Sencha.Channel.Roster, ^channel_hash, _targets, %Sencha.Channel{name: real_channel},
           modes}
        ] ->
          Sencha.User.message_send(
            socket,
            Sencha.User.Numeric.encode(:RPL_CHANNELMODEIS, target, %{
              channel: real_channel,
              adding?: true,
              modes_map:
                modes
                |> Enum.filter(fn {k, _} -> k in @modes_viewable_by_default end)
            }),
            target
          )
      end
    end)

    state
  end

  def handle(state, _socket, _message) do
    state
  end
end
