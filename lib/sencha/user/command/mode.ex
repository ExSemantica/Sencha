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
  @modes_viewable_by_default [?n]
  # TODO: user modes?
  def handle(
        state = %Sencha.User{target: target},
        socket,
        %Sencha.Message{middle: ["#" <> channel]}
      ) do
    :mnesia.transaction(fn ->
      case :mnesia.read(Sencha.Channel.Roster, String.downcase("#" <> channel)) do
        [] ->
          # Nobody on this channel
          Sencha.User.message_send(
            socket,
            Sencha.User.Numeric.encode(:ERR_NOSUCHCHANNEL, target, %{
              channel: "#" <> channel
            })
          )

        [
          {Sencha.Channel.Roster, real_channel, _targets, _attributes, modes}
        ] ->
          Sencha.User.message_send(
            socket,
            Sencha.User.Numeric.encode(:RPL_CHANNELMODEIS, target, %{
              channel: real_channel,
              adding?: true,
              modes_map:
                modes
                |> Enum.filter(fn {k, _} -> k in @modes_viewable_by_default end)
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
