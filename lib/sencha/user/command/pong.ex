# Dispatch IRCv3 command PONG
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
defmodule Sencha.User.Command.Pong do
  @moduledoc false
  def handle(
        state = %Sencha.User{
          last_token: last_token,
          timeout_ping_soft: soft,
          timeout_ping_hard: hard
        },
        _socket,
        %Sencha.Message{middle: [token]}
      ) do
    if token == "Sencha-#{last_token}" do
      Process.cancel_timer(soft)
      Process.cancel_timer(hard)

      %Sencha.User{
        state
        | last_token: DateTime.utc_now() |> DateTime.to_unix(),
          timeout_ping_soft: Process.send_after(self(), :ping_soft, Sencha.User.ping_soft()),
          timeout_ping_hard: Process.send_after(self(), :ping_hard, Sencha.User.ping_hard())
      }
    else
      state
    end
  end

  def handle(state, socket, message = %Sencha.Message{middle: [], trailing: token}) when not is_nil(token) do
    handle(state, socket, %Sencha.Message{
      message
      | middle: token |> String.split(" "),
        trailing: nil
    })
  end

  def handle(state, _socket, _message) do
    state
  end
end
