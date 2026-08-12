# Send welcome burst to user
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
defmodule Sencha.User.Welcome do
  @moduledoc false
  def send_burst(state = %Sencha.User{target: target}, socket) do
    supported = Sencha.ISupport.get() |> Enum.chunk_every(13)

    welcome_burst =
      [
        Sencha.User.Numeric.encode(:RPL_WELCOME, state.target),
        Sencha.User.Numeric.encode(:RPL_YOURHOST, state.target),
        Sencha.User.Numeric.encode(:RPL_CREATED, state.target),
        Sencha.User.Numeric.encode(:RPL_MYINFO, state.target),
        for s <- supported do
          Sencha.User.Numeric.encode(:RPL_ISUPPORT, state.target, %{features: s})
        end
      ]
      |> List.flatten()

    for w <- welcome_burst do
      Sencha.User.message_send(socket, w, target)
    end

    Sencha.User.Command.handle(state, socket, %Sencha.Message{command: "LUSERS"})
    Sencha.User.Command.handle(state, socket, %Sencha.Message{command: "MOTD"})

    state
  end
end
