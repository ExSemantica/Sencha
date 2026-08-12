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
defmodule Sencha.User.Command.User do
  @moduledoc false
  require Logger

  def handle(
        state = %Sencha.User{
          target: target,
          registered_attributes: registered,
          capabilities: caps_state
        },
        socket,
        %Sencha.Message{
          middle: [ident, _nc0, _nc1],
          trailing: realname
        }
      ) do
    if MapSet.member?(registered, :user) do
      Sencha.User.message_send(
        socket,
        Sencha.User.Numeric.encode(:ERR_ALREADYREGISTERED, target),
        target
      )

      state
    else
      state =
        case caps_state do
          :wait_for_caps ->
            Logger.debug("Will ignore CAP handshake due to premature recv of USER")
            %Sencha.User{state | capabilities: :ignore}

          _other ->
            state
        end

      cond do
        Sencha.Constrain.User.check_ident?(ident) and is_nil(realname) ->
          %Sencha.User{
            state
            | registered_attributes: MapSet.put(registered, :user),
              target: %{target | user: ident}
          }

        Sencha.Constrain.User.check_ident?(ident) and Sencha.Constrain.User.check_gecos?(realname) ->
          %Sencha.User{
            state
            | registered_attributes: MapSet.put(registered, :user),
              gecos: realname,
              target: %{target | user: ident}
          }

        true ->
          state
      end
    end
  end

  def handle(state = %Sencha.User{target: target}, socket, message)
      when length(message.middle) < 3 do
    Sencha.User.message_send(
      socket,
      Sencha.User.Numeric.encode(:ERR_NEEDMOREPARAMS, target, %{command: "USER"}),
      target
    )

    state
  end

  def handle(state, socket, message = %Sencha.Message{middle: [ident, nc0, nc1 | realname]}) do
    handle(state, socket, %Sencha.Message{
      message
      | middle: [ident, nc0, nc1],
        trailing: realname |> Enum.join(" ")
    })
  end

  def handle(state, _socket, _message) do
    state
  end
end
