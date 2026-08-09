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
defmodule Sencha.Dispatch.User do
  @moduledoc false
  require Logger

  def handle(state = %{user?: true}, _message) do
    state |> Sencha.Dispatch.Numeric.send(:ERR_ALREADYREGISTERED)
  end

  def handle(state, message = %Sencha.Message{})
      when length(message.middle) < 3 do
    state |> Sencha.Dispatch.Numeric.send(:ERR_NEEDMOREPARAMS, %{command: "USER"})
  end

  def handle(state = %Sencha.User{target: target, capabilities: caps_state}, %Sencha.Message{
        middle: [ident, _nc0, _nc1],
        trailing: realname
      }) do
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
        %Sencha.User{state | user?: true, target: %{target | user: ident}}

      Sencha.Constrain.User.check_ident?(ident) and Sencha.Constrain.User.check_gecos?(realname) ->
        %Sencha.User{state | user?: true, gecos: realname, target: %{target | user: ident}}

      true ->
        state
    end
  end

  def handle(state, message = %Sencha.Message{middle: [ident, nc0, nc1 | realname]}) do
    handle(state, %Sencha.Message{
      message
      | middle: [ident, nc0, nc1],
        trailing: realname |> Enum.join(" ")
    })
  end

  def handle(state, _message) do
    state
  end
end
