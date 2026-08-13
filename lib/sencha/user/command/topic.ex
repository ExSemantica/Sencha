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
          middle: [channel],
          trailing: nil
        }
      ) do
    channel_hash = String.downcase(channel)

    :mnesia.transaction(fn ->
      case :mnesia.read(Sencha.Channel.Roster, channel_hash) do
        [] ->
          # Nobody on this channel
          Sencha.User.message_send(
            socket,
            Sencha.User.Numeric.encode(:ERR_NOSUCHCHANNEL, target, %{
              channel: channel
            }),
            target
          )

        [
          {Sencha.Channel.Roster, ^channel_hash, targets,
           %Sencha.Channel{
             name: real_channel,
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
                }),
                target
              )

            is_nil(topic) ->
              Sencha.User.message_send(
                socket,
                Sencha.User.Numeric.encode(:RPL_NOTOPIC, target, %{
                  channel: real_channel
                }),
                target
              )

            true ->
              Sencha.User.message_send(
                socket,
                Sencha.User.Numeric.encode(:RPL_TOPIC, target, %{
                  channel: real_channel,
                  topic: topic
                }),
                target
              )

              Sencha.User.message_send(
                socket,
                Sencha.User.Numeric.encode(:RPL_TOPICWHOTIME, target, %{
                  channel: real_channel,
                  who: topic_changed_by,
                  set_at: topic_changed |> DateTime.to_unix()
                }),
                target
              )
          end
      end
    end)

    state
  end

  def handle(
        state = %Sencha.User{target: target},
        socket,
        %Sencha.Message{
          middle: [channel],
          trailing: trailing
        }
      ) do
    channel_hash = String.downcase(channel)

    :mnesia.transaction(fn ->
      case :mnesia.read(Sencha.Channel.Roster, channel_hash) do
        [] ->
          # Nobody on this channel
          Sencha.User.message_send(
            socket,
            Sencha.User.Numeric.encode(:ERR_NOSUCHCHANNEL, target, %{
              channel: channel
            }),
            target
          )

        [
          {Sencha.Channel.Roster, ^channel_hash, targets, %Sencha.Channel{name: real_channel},
           modes = %{?o => operators}}
        ] ->
          # People are on this channel
          cond do
            target not in targets ->
              Sencha.User.message_send(
                socket,
                Sencha.User.Numeric.encode(:ERR_NOTONCHANNEL, target, %{
                  channel: real_channel
                }),
                target
              )

            Map.has_key?(modes, ?t) and target not in operators ->
              Sencha.User.message_send(
                socket,
                Sencha.User.Numeric.encode(:ERR_CHANOPPRIVSNEEDED, target, %{
                  channel: real_channel
                }),
                target
              )

            true ->
              Sencha.Channel.update_topic(channel_hash, trailing, target)
          end
      end
    end)

    state
  end

  def handle(state = %Sencha.User{target: target}, socket, %Sencha.Message{middle: []}) do
    Sencha.User.message_send(
      socket,
      Sencha.User.Numeric.encode(:ERR_NEEDMOREPARAMS, target, %{
        command: "TOPIC"
      }),
      target
    )

    state
  end

  def handle(state, _socket, _message) do
    state
  end
end
