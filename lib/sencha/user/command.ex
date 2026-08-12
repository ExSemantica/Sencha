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
    state |> handle_registered(socket, &(&1 |> __MODULE__.Lusers.handle(socket, message)))
  end

  def handle(state = %Sencha.User{}, socket, message = %Sencha.Message{command: "MOTD"}) do
    state |> handle_registered(socket, &(&1 |> __MODULE__.Motd.handle(socket, message)))
  end

  def handle(state = %Sencha.User{}, socket, message = %Sencha.Message{command: "CAP"}) do
    state |> __MODULE__.Cap.handle(socket, message)
  end

  def handle(state = %Sencha.User{}, socket, message = %Sencha.Message{command: "QUIT"}) do
    state |> __MODULE__.Quit.handle(socket, message)
  end

  def handle(state = %Sencha.User{}, socket, message = %Sencha.Message{command: "JOIN"}) do
    state |> handle_registered(socket, &(&1 |> __MODULE__.Join.handle(socket, message)))
  end

  def handle(state = %Sencha.User{}, socket, message = %Sencha.Message{command: "PART"}) do
    state |> handle_registered(socket, &(&1 |> __MODULE__.Part.handle(socket, message)))
  end

  def handle(state = %Sencha.User{}, socket, message = %Sencha.Message{command: "TOPIC"}) do
    state |> handle_registered(socket, &(&1 |> __MODULE__.Topic.handle(socket, message)))
  end

  def handle(state = %Sencha.User{}, socket, message = %Sencha.Message{command: "NAMES"}) do
    state |> handle_registered(socket, &(&1 |> __MODULE__.Names.handle(socket, message)))
  end

  def handle(state = %Sencha.User{}, socket, message = %Sencha.Message{command: "MODE"}) do
    state |> handle_registered(socket, &(&1 |> __MODULE__.Mode.handle(socket, message)))
  end

  def handle(state = %Sencha.User{}, socket, message = %Sencha.Message{command: "PRIVMSG"}) do
    state |> handle_registered(socket, &(&1 |> __MODULE__.Privmsg.handle(socket, message)))
  end

  def handle(state = %Sencha.User{}, socket, message = %Sencha.Message{command: "NOTICE"}) do
    state |> handle_registered(socket, &(&1 |> __MODULE__.Notice.handle(socket, message)))
  end

  def handle(state = %Sencha.User{}, socket, message = %Sencha.Message{command: "AWAY"}) do
    state |> handle_registered(socket, &(&1 |> __MODULE__.Away.handle(socket, message)))
  end

  def handle(state = %Sencha.User{}, socket, message = %Sencha.Message{command: "WHO"}) do
    state |> handle_registered(socket, &(&1 |>  __MODULE__.Who.handle(socket, message)))
  end

  def handle(state = %Sencha.User{}, socket, message = %Sencha.Message{command: "TAGMSG"}) do
    state |> handle_registered(socket, &(&1 |>  __MODULE__.Tagmsg.handle(socket, message)))
  end

  def handle(state = %Sencha.User{}, _socket, message = %Sencha.Message{}) do
    Logger.warning("Unknown command received, check debug log")
    Logger.debug(message)

    state
  end

  defp handle_registered(
         state = %Sencha.User{registered_attributes: registered, target: target},
         socket,
         fun
       ) do
    registered? = MapSet.subset?(Sencha.User.registered_fully(), registered)

    if registered? do
      state
      |> fun.()
    else
      Sencha.User.message_send(
        socket,
        Sencha.User.Numeric.encode(:ERR_NOTREGISTERED, target),
        target
      )

      state
    end
  end
end
