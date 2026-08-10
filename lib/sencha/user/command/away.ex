# Dispatch IRCv3 command AWAY
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
defmodule Sencha.User.Command.Away do
  @moduledoc false
  def handle(
        state = %Sencha.User{target: target},
        socket,
        %Sencha.Message{
          trailing: nil
        }
      ) do
    Sencha.User.message_send(
      socket,
      Sencha.User.Numeric.encode(:RPL_UNAWAY, target)
    )

    %Sencha.User{state | away_status: nil}
  end

  def handle(
        state = %Sencha.User{target: target},
        socket,
        %Sencha.Message{
          trailing: status
        }
      ) do
    if byte_size(status) <= Sencha.Constrain.User.max_length_away() do
      Sencha.User.message_send(
        socket,
        Sencha.User.Numeric.encode(:RPL_NOWAWAY, target)
      )

      %Sencha.User{state | away_status: status}
    else
      state
    end
  end

  def handle(state, _socket, _message) do
    state
  end
end
