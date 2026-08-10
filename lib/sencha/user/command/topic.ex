# Dispatch IRCv3 command TOPIC
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
defmodule Sencha.User.Command.Topic do
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
            Sencha.User.Numeric.encode(:ERR_NOSUCHCHANNEL, target, %{
              channel: channel
            })
          )

        [
          {Sencha.Channel.Roster, real_channel, targets,
           %Sencha.Channel{
             topic: topic,
             topic_changed: topic_changed,
             topic_changed_by: topic_changed_by
           }, _modes}
        ] ->
          # People are on this channel
          cond do
            target not in targets ->
              Sencha.User.message_send(
                socket,
                Sencha.User.Numeric.encode(:ERR_NOTONCHANNEL, target, %{
                  channel: real_channel
                })
              )

            is_nil(topic) ->
              Sencha.User.message_send(
                socket,
                Sencha.User.Numeric.encode(:RPL_NOTOPIC, target, %{
                  channel: real_channel
                })
              )

            true ->
              Sencha.User.message_send(
                socket,
                Sencha.User.Numeric.encode(:RPL_TOPIC, target, %{
                  channel: real_channel,
                  topic: topic
                })
              )

              Sencha.User.message_send(
                socket,
                Sencha.User.Numeric.encode(:RPL_TOPICWHOTIME, target, %{
                  channel: real_channel,
                  who: topic_changed_by,
                  set_at: topic_changed |> DateTime.to_unix()
                })
              )
          end
      end
    end)

    state
  end

  def handle(state, _socket, _message) do
    state
  end
end
