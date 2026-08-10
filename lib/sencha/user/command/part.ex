# Dispatch IRCv3 command PART
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
defmodule Sencha.User.Command.Part do
  @moduledoc false
  def handle(
        state = %Sencha.User{target: target},
        socket,
        %Sencha.Message{
          middle: [channel | reason]
        }
      ) do
    state |> Sencha.Channel.part(socket, channel, target, reason |> Enum.join(" "))
  end

  def handle(state, _socket, _message) do
    state
  end
end
