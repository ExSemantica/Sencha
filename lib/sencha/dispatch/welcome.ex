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
defmodule Sencha.Dispatch.Welcome do
  @moduledoc false
  def send_burst(state = %{socket: socket_pid, target: target}) do
    Sencha.Socket.message_send(
      socket_pid,
      %Sencha.Message{
        prefix: Application.fetch_env!(:sencha, :hostname),
        command: "001",
        middle: [target.nickname],
        trailing: "Welcome, #{target |> Sencha.Prefix.encode()}"
      }
    )

    Sencha.Socket.message_send(
      socket_pid,
      %Sencha.Message{
        prefix: Application.fetch_env!(:sencha, :hostname),
        command: "002",
        middle: [target.nickname],
        trailing:
          "Your host is #{Application.fetch_env!(:sencha, :hostname)} running Sencha IRC #{:persistent_term.get(Sencha.Version)}"
      }
    )

    state
  end
end
