# Dispatch IRCv3 command NOTICE
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
defmodule Sencha.User.Command.Notice do
  @moduledoc false

  def handle(
        state = %Sencha.User{target: target},
        socket,
        %Sencha.Message{middle: ["#" <> channel], trailing: text, tags: tags}
      ) do
    :mnesia.transaction(fn ->
      case :mnesia.read(Sencha.Channel.Roster, String.downcase("#" <> channel)) do
        [] ->
          :ok

        [
          broadcast
        ] ->
          Sencha.Channel.try_broadcast(
            broadcast,
            target,
            fn real_channel, sender, recipient ->
              Sencha.User.remote_send(
                %Sencha.Message{
                  prefix: sender,
                  command: "NOTICE",
                  middle: [real_channel],
                  trailing: text
                },
                String.downcase(recipient.nickname),
                tags
              )
            end,
            %{
              on_not_in_channel: fn ->
                Sencha.User.message_send(
                  socket,
                  Sencha.User.Numeric.encode(:ERR_CANNOTSENDTOCHAN, target, %{
                    channel: channel
                  }),
                  target
                )
              end
            }
          )
      end
    end)

    state
  end

  def handle(
        state = %Sencha.User{target: target},
        socket,
        %Sencha.Message{middle: [user], trailing: text, tags: tags}
      ) do
    user_hash = String.downcase(user)

    case :global.whereis_name({Sencha.User, user_hash}) do
      :undefined ->
        Sencha.User.message_send(
          socket,
          Sencha.User.Numeric.encode(:ERR_NOSUCHNICK, target, %{
            nick: user
          }),
          target
        )

      _pid ->
        Sencha.User.send_away_status(user_hash, target)

        Sencha.User.remote_send(
          %Sencha.Message{
            prefix: target |> Sencha.Prefix.encode(),
            command: "NOTICE",
            middle: [target.nickname],
            trailing: text
          },
          user_hash,
          tags
        )
    end

    state
  end

  def handle(state, socket, message = %Sencha.Message{middle: [user, one]}) do
    handle(state, socket, %Sencha.Message{message | middle: [user], trailing: one})
  end

  def handle(state, _socket, _message) do
    state
  end
end
