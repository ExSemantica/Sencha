# Dispatch IRCv3 command WHO
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
defmodule Sencha.User.Command.Who do
  @moduledoc false

  def handle(
        state = %Sencha.User{target: target},
        socket,
        %Sencha.Message{middle: ["#" <> channel]}
      ) do
    channel_hash = String.downcase("#" <> channel)

    :mnesia.transaction(fn ->
      case :mnesia.read(Sencha.Channel.Roster, channel_hash) do
        [] ->
          Sencha.User.message_send(
            socket,
            Sencha.User.Numeric.encode(:RPL_ENDOFWHO, target, %{
              mask: "#" <> channel
            }),
            target
          )

        [
          {Sencha.Channel.Roster, ^channel_hash, targets, %Sencha.Channel{name: real_channel},
           _modes}
        ] ->
          # NOTE: Erlang has a global counter functionality so we can use that
          # in order to synchronize the WHO responses

          counter = :counters.new(1, [:atomics])
          :counters.put(counter, 1, length(targets))

          for t <- targets do
            user_hash = String.downcase(t.nickname)
            Sencha.User.send_who(user_hash, target, counter, real_channel)
          end
      end
    end)

    state
  end

  def handle(
        state = %Sencha.User{target: target},
        socket,
        %Sencha.Message{middle: [mask]}
      ) do
    # TODO: Masks would be hard to implement in this distributed architecture

    Sencha.User.message_send(
      socket,
      Sencha.User.Numeric.encode(:RPL_ENDOFWHO, target, %{
        mask: mask
      }),
      target
    )

    state
  end

  def handle(state, _socket, _message) do
    state
  end
end
