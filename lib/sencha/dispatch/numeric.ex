# Send numerics to user
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
defmodule Sencha.Dispatch.Numeric do
  @moduledoc """
  Send numerics to user
  """

  @doc """
  Send a numeric to the user given the official IRCv3 name of it
  """
  def send(state, numeric, params \\ [])
  # ===========================================================================
  # Replies
  # ===========================================================================

  def send(state = %{socket: socket_pid, target: target}, :RPL_WELCOME, _params) do
    Sencha.Socket.message_send(
      socket_pid,
      %Sencha.Message{
        prefix: Application.fetch_env!(:sencha, :hostname),
        command: "001",
        middle: [target.nickname],
        trailing: "Welcome, #{target |> Sencha.Prefix.encode()}"
      }
    )

    state
  end

  def send(state = %{socket: socket_pid, target: target}, :RPL_YOURHOST, _params) do
    Sencha.Socket.message_send(
      socket_pid,
      %Sencha.Message{
        prefix: Application.fetch_env!(:sencha, :hostname),
        command: "002",
        middle: [target.nickname],
        trailing:
          "Your host is #{Application.fetch_env!(:sencha, :hostname)} running Sencha IRC v#{:persistent_term.get(Sencha.Version)}"
      }
    )

    state
  end

  def send(state = %{socket: socket_pid, target: target}, :RPL_CREATED, _params) do
    Sencha.Socket.message_send(
      socket_pid,
      %Sencha.Message{
        prefix: Application.fetch_env!(:sencha, :hostname),
        command: "003",
        middle: [target.nickname],
        trailing:
          "This server was started on #{:persistent_term.get(Sencha.CreationDate) |> DateTime.to_iso8601()}"
      }
    )

    state
  end

  def send(state = %{socket: socket_pid, target: target}, :RPL_MYINFO, _params) do
    Sencha.Socket.message_send(
      socket_pid,
      %Sencha.Message{
        prefix: Application.fetch_env!(:sencha, :hostname),
        command: "004",
        middle: [
          target.nickname,
          Application.fetch_env!(:sencha, :hostname),
          :persistent_term.get(Sencha.Version),
          Sencha.User.modes_all() |> MapSet.to_list() |> to_string,
          Sencha.Channel.modes_noparam_all() |> MapSet.to_list() |> to_string,
          Sencha.Channel.modes_param_all() |> MapSet.to_list() |> to_string
        ]
      }
    )

    state
  end

  # ===========================================================================
  # Errors
  # ===========================================================================
  def send(state = %{socket: socket_pid, target: target}, :ERR_NONICKNAMEGIVEN, _params) do
    Sencha.Socket.message_send(
      socket_pid,
      %Sencha.Message{
        prefix: Application.fetch_env!(:sencha, :hostname),
        command: "431",
        middle: [target[:nickname] || "*"],
        trailing: "No nickname given"
      }
    )

    state
  end

  def send(state = %{socket: socket_pid, target: target}, :ERR_ERRONEOUSNICKNAME, _params) do
    Sencha.Socket.message_send(
      socket_pid,
      %Sencha.Message{
        prefix: Application.fetch_env!(:sencha, :hostname),
        command: "432",
        middle: [target[:nickname] || "*"],
        trailing: "Erroneous nickname"
      }
    )

    state
  end

  def send(state = %{socket: socket_pid, target: target}, :ERR_NICKNAMEINUSE, _params) do
    Sencha.Socket.message_send(
      socket_pid,
      %Sencha.Message{
        prefix: Application.fetch_env!(:sencha, :hostname),
        command: "433",
        middle: [target[:nickname] || "*"],
        trailing: "Nickname already in use"
      }
    )

    state
  end

  def send(state = %{socket: socket_pid, target: target}, :ERR_NEEDMOREPARAMS, %{command: command}) do
    Sencha.Socket.message_send(
      socket_pid,
      %Sencha.Message{
        prefix: Application.fetch_env!(:sencha, :hostname),
        command: "461",
        middle: [target[:nickname] || "*", command],
        trailing: "Not enough parameters"
      }
    )

    state
  end

  def send(state = %{socket: socket_pid, target: target}, :ERR_ALREADYREGISTERED, _params) do
    Sencha.Socket.message_send(
      socket_pid,
      %Sencha.Message{
        prefix: Application.fetch_env!(:sencha, :hostname),
        command: "462",
        middle: [target[:nickname] || "*"],
        trailing: "You may not re-register"
      }
    )

    state
  end

  def send(state = %{socket: socket_pid, target: target}, :ERR_YOUREBANNEDCREEP, _params) do
    Sencha.Socket.message_send(
      socket_pid,
      %Sencha.Message{
        prefix: Application.fetch_env!(:sencha, :hostname),
        command: "465",
        middle: [target[:nickname] || "*"],
        trailing: "You have been banned from this IRC server"
      }
    )

    state
  end
end
