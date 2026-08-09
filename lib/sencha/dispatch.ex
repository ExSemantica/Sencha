# Dispatch Sencha.Message for Sencha.User
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
defmodule Sencha.Dispatch do
  @moduledoc """
  Dispatch `Sencha.Message` for `Sencha.User`
  """
  require Logger

  def handle(state = %Sencha.User{}, message = %Sencha.Message{command: "USER"}) do
    state |> __MODULE__.User.handle(message)
  end

  def handle(state = %Sencha.User{}, message = %Sencha.Message{command: "NICK"}) do
    state |> __MODULE__.Nick.handle(message)
  end

  def handle(state = %Sencha.User{}, message = %Sencha.Message{command: "PING"}) do
    state |> __MODULE__.Ping.handle(message)
  end

  def handle(state = %Sencha.User{}, message = %Sencha.Message{command: "PONG"}) do
    state |> __MODULE__.Pong.handle(message)
  end

  def handle(state = %Sencha.User{}, message = %Sencha.Message{command: "LUSERS"}) do
    state |> __MODULE__.Lusers.handle(message)
  end

  def handle(state = %Sencha.User{}, message = %Sencha.Message{command: "MOTD"}) do
    state |> __MODULE__.Motd.handle(message)
  end

  def handle(state = %Sencha.User{}, _message) do
    Logger.warning("Unimplemented IRC command")
    state
  end
end
