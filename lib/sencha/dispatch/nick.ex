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
        state = %{socket: socket_pid, target: target},
        %Sencha.Message{middle: [nick]}
      ) do
    nick_ok? = Sencha.Constrain.User.check_name?(nick)
    nick_hash = String.downcase(nick)

    if nick_ok? do
      # NOTE: We send a lowercase version of the nickname as the hash
      # Therefore, we make it *case-insensitive*
      previous_nick = target[:nickname]

      case Sencha.Socket.send_nickname_hash(socket_pid, nick_hash) do
        :yes when is_nil(previous_nick) ->
          %{state | nick?: true} |> put_in([:target, :nickname], nick)

        :yes ->
          Sencha.Socket.message_send(
            socket_pid,
            %Sencha.Message{
              prefix: target |> Sencha.Prefix.encode(),
              command: "NICK",
              middle: nick
            }
          )

          %{state | nick?: true} |> put_in([:target, :nickname], nick)

        :already_in_use ->
          state |> Sencha.Dispatch.Numeric.send(:ERR_NICKNAMEINUSE)
      end
    else
      state |> Sencha.Dispatch.Numeric.send(:ERR_ERRONEOUSNICKNAME)
    end
  end

  def handle(
        state,
        %Sencha.Message{middle: []}
      ) do
    state |> Sencha.Dispatch.Numeric.send(:ERR_NONICKNAMEGIVEN)
  end

  def handle(state, _message) do
    state
  end
end
