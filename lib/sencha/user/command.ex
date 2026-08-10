# Receive IRCv3 commands
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
defmodule Sencha.User.Command do
  @moduledoc """
  Receive IRCv3 commands
  """
  require Logger

  def handle(state = %Sencha.User{}, socket, message = %Sencha.Message{command: "USER"}) do
    state |> __MODULE__.User.handle(socket, message)
  end

  def handle(state = %Sencha.User{}, socket, message = %Sencha.Message{command: "NICK"}) do
    state |> __MODULE__.Nick.handle(socket, message)
  end

  def handle(state = %Sencha.User{}, socket, message = %Sencha.Message{command: "PING"}) do
    state |> __MODULE__.Ping.handle(socket, message)
  end

  def handle(state = %Sencha.User{}, socket, message = %Sencha.Message{command: "PONG"}) do
    state |> __MODULE__.Pong.handle(socket, message)
  end

  def handle(state = %Sencha.User{}, socket, message = %Sencha.Message{command: "LUSERS"}) do
    state |> __MODULE__.Lusers.handle(socket, message)
  end

  def handle(state = %Sencha.User{}, socket, message = %Sencha.Message{command: "MOTD"}) do
    state |> __MODULE__.Motd.handle(socket, message)
  end

  def handle(state = %Sencha.User{}, socket, message = %Sencha.Message{command: "CAP"}) do
    state |> __MODULE__.Cap.handle(socket, message)
  end

  def handle(state = %Sencha.User{}, socket, message = %Sencha.Message{command: "QUIT"}) do
    state |> __MODULE__.Quit.handle(socket, message)
  end

  def handle(state = %Sencha.User{}, socket, message = %Sencha.Message{command: "JOIN"}) do
    state |> __MODULE__.Join.handle(socket, message)
  end

  def handle(state = %Sencha.User{}, socket, message = %Sencha.Message{command: "PART"}) do
    state |> __MODULE__.Part.handle(socket, message)
  end

  def handle(state = %Sencha.User{}, _socket, message = %Sencha.Message{}) do
    Logger.warning("Unknown command received, check debug log")
    Logger.debug(message)

    state
  end
end
