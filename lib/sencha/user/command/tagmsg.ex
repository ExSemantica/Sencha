# Dispatch IRCv3 command TAGMSG
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
defmodule Sencha.User.Command.Tagmsg do
  @moduledoc false
  def handle(
        state = %Sencha.User{capabilities: caps, target: target},
        _socket,
        %Sencha.Message{middle: ["#" <> channel], tags: tags}
      ) do
    tags? =
      case caps do
        {:ok, check_cap} when not is_nil(tags) -> MapSet.member?(check_cap, "message-tags")
        _ -> false
      end

    if tags? do
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
                    command: "TAGMSG",
                    middle: [real_channel]
                  },
                  String.downcase(recipient.nickname),
                  tags
                )
              end,
              %{}
            )
        end
      end)
    end

    state
  end

  def handle(
        state = %Sencha.User{target: target},
        _socket,
        %Sencha.Message{middle: [user], tags: tags}
      ) do
    user_hash = String.downcase(user)

    case :global.whereis_name({Sencha.User, user_hash}) do
      :undefined ->
        :ok

      _pid ->
        Sencha.User.send_away_status(user_hash, target)

        Sencha.User.remote_send(
          %Sencha.Message{
            prefix: target |> Sencha.Prefix.encode(),
            command: "TAGMSG",
            middle: [target.nickname]
          },
          user_hash,
          tags
        )
    end

    state
  end

  def handle(state, _socket, _message) do
    state
  end
end
