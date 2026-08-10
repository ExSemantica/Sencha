# Dispatch IRCv3 command USER
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
defmodule Sencha.User.Command.Names do
  @moduledoc false

  def handle(
        state = %Sencha.User{target: target},
        socket,
        %Sencha.Message{
          middle: [channel]
        }
      ) do
    :mnesia.transaction(fn ->
      case :mnesia.read(Sencha.Channel.Roster, String.downcase(channel)) do
        [] ->
          # Nobody on this channel
          Sencha.User.message_send(
            socket,
            Sencha.User.Numeric.encode(:RPL_ENDOFNAMES, target, %{
              channel: channel
            })
          )

        [{Sencha.Channel.Roster, _channel, targets, _attributes, modes}] ->
          # People are on this channel
          users_prefixes =
            targets
            |> Enum.map(fn t ->
              matchee = Sencha.Prefix.encode(t)
              oper? = modes[?o] |> Enum.any?(& Sencha.Mask.match?(matchee, &1))
              voice? = modes[?v] |> Enum.any?(& Sencha.Mask.match?(matchee, &1))

              cond do
                oper? ->
                  "@" <> t.nickname

                voice? ->
                  "+" <> t.nickname

                true ->
                  t.nickname
              end
            end)

          Sencha.User.message_send(
            socket,
            Sencha.User.Numeric.encode(:RPL_NAMREPLY, target, %{
              channel: channel,
              user_data: users_prefixes
            })
          )

          Sencha.User.message_send(
            socket,
            Sencha.User.Numeric.encode(:RPL_ENDOFNAMES, target, %{
              channel: channel
            })
          )
      end
    end)

    state
  end

  def handle(state, _socket, _message) do
    state
  end
end
