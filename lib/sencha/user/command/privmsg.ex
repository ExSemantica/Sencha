# Dispatch IRCv3 command PRIVMSG
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
defmodule Sencha.User.Command.Privmsg do
  @moduledoc false

  def handle(
        state = %Sencha.User{target: target},
        socket,
        %Sencha.Message{middle: ["#" <> channel], trailing: text}
      ) do
    :mnesia.transaction(fn ->
      case :mnesia.read(Sencha.Channel.Roster, String.downcase("#" <> channel)) do
        [] ->
          :ok

        [
          {Sencha.Channel.Roster, real_channel, targets, _attributes, modes}
        ] ->
          matchee = target |> Sencha.Prefix.encode()

          banned? =
            modes[?b]
            |> Enum.any?(&Sencha.Mask.match?(matchee, &1 |> Sencha.Prefix.encode()))

          exception? =
            modes[?e]
            |> Enum.any?(&Sencha.Mask.match?(matchee, &1 |> Sencha.Prefix.encode()))

          cond do
            banned? and not exception? ->
              # Silently fail if this user is banned
              :ok

            Map.has_key?(modes, ?n) and target not in targets ->
              Sencha.User.message_send(
                socket,
                Sencha.User.Numeric.encode(:ERR_CANNOTSENDTOCHAN, target, %{
                  channel: channel
                })
              )

            true ->
              origin = target |> Sencha.Prefix.encode()

              for t <- targets do
                if target != t do
                  Sencha.User.remote_send(
                    %Sencha.Message{
                      prefix: origin,
                      command: "PRIVMSG",
                      middle: [real_channel],
                      trailing: text
                    },
                    String.downcase(t.nickname)
                  )
                end
              end
          end
      end
    end)

    state
  end

  def handle(
        state = %Sencha.User{target: target},
        socket,
        %Sencha.Message{middle: [user], trailing: text}
      ) do
    user_hash = String.downcase(user)

    case :global.whereis_name({Sencha.User, user_hash}) do
      :undefined ->
        Sencha.User.message_send(
          socket,
          Sencha.User.Numeric.encode(:ERR_NOSUCHNICK, target, %{
            nick: user
          })
        )

      _pid ->
        Sencha.User.send_away_status(user_hash, String.downcase(target.nickname))

        Sencha.User.remote_send(
          %Sencha.Message{
            prefix: target |> Sencha.Prefix.encode(),
            command: "PRIVMSG",
            middle: [target.nickname],
            trailing: text
          },
          user_hash
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
