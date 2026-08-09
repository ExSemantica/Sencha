# Dispatch IRCv3 command NICK
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
defmodule Sencha.Dispatch.Nick do
  @moduledoc false
  def handle(
        state = %Sencha.User{target: target},
        %Sencha.Message{middle: [nick]}
      ) do
    nick_ok? = Sencha.Constrain.User.check_name?(nick)
    nick_hash = String.downcase(nick)

    if nick_ok? do
      # NOTE: We send a lowercase version of the nickname as the hash
      # Therefore, we make it *case-insensitive*
      previous_nick = target[:nickname]
      previous_nick_hash = String.downcase(target[:nickname] || nick)

      pid = self()

      hash_ok? =
        case :global.whereis_name({Sencha.User, previous_nick_hash}) do
          :undefined ->
            :global.register_name({Sencha.User, nick_hash}, pid)

          ^pid ->
            :global.re_register_name({Sencha.User, nick_hash}, pid)

          _other ->
            :already_in_use
        end

      case hash_ok? do
        :yes when is_nil(previous_nick) ->
          %Sencha.User{state | nick?: true, target: %{target | nickname: nick}}

        :yes ->
          Sencha.User.message_send(
            self(),
            %Sencha.Message{
              prefix: target |> Sencha.Prefix.encode(),
              command: "NICK",
              middle: nick
            }
          )

          %{state | nick?: true, target: %{target | nickname: nick}}

        :already_in_use ->
          Sencha.User.message_send(
            self(),
            %Sencha.Message{
              prefix: Application.fetch_env!(:sencha, :hostname),
              command: "433",
              middle: [target[:nickname] || "*"],
              trailing: "Nickname already in use"
            }
          )

          state
      end
    else
      Sencha.User.message_send(
        self(),
        %Sencha.Message{
          prefix: Application.fetch_env!(:sencha, :hostname),
          command: "432",
          middle: [target[:nickname] || "*"],
          trailing: "Erroneous nickname"
        }
      )

      state
    end
  end

  def handle(
        state = %Sencha.User{target: target},
        %Sencha.Message{middle: []}
      ) do
    Sencha.User.message_send(
      self(),
      %Sencha.Message{
        prefix: Application.fetch_env!(:sencha, :hostname),
        command: "431",
        middle: [target[:nickname] || "*"],
        trailing: "No nickname given"
      }
    )

    state
  end

  def handle(state, _message) do
    state
  end
end
