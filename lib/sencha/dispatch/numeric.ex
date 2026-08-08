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

  def send(state = %{target: target}, :RPL_WELCOME, _params) do
    Sencha.User.message_send(
      self(),
      %Sencha.Message{
        prefix: Application.fetch_env!(:sencha, :hostname),
        command: "001",
        middle: [target.nickname],
        trailing: "Welcome, #{target |> Sencha.Prefix.encode()}"
      }
    )

    state
  end

  def send(state = %{target: target}, :RPL_YOURHOST, _params) do
    Sencha.User.message_send(
      self(),
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

  def send(state = %{target: target}, :RPL_CREATED, _params) do
    Sencha.User.message_send(
      self(),
      %Sencha.Message{
        prefix: Application.fetch_env!(:sencha, :hostname),
        command: "003",
        middle: [target.nickname],
        trailing:
          "This server was started on #{:persistent_term.get(Sencha.CreationDate) |> Calendar.strftime("%c")}"
      }
    )

    state
  end

  def send(state = %{target: target}, :RPL_MYINFO, _params) do
    Sencha.User.message_send(
      self(),
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

  def send(state = %{target: target}, :RPL_LOCALUSERS, _params) do
    {:ok, connections} = Sencha.User.gather()
    connections_num = length(connections)
    connections_max = :persistent_term.get(Sencha.User.Max, 0)
    connections_max = max(connections_max, connections_num)

    connections_max =
      if connections_num > connections_max do
        :persistent_term.put(Sencha.User.Max, connections_num)
      else
        connections_max
      end

    Sencha.User.message_send(
      self(),
      %Sencha.Message{
        prefix: Application.fetch_env!(:sencha, :hostname),
        command: "265",
        middle: [
          target.nickname,
          connections_num |> to_string,
          connections_max |> to_string
        ],
        trailing: "Current local users #{connections_num}, max #{connections_max}"
      }
    )

    state
  end

  # ===========================================================================
  # Errors
  # ===========================================================================
  def send(state = %{target: target}, :ERR_NONICKNAMEGIVEN, _params) do
    Sencha.User.message_send(
      self(),
      %Sencha.Message{
        prefix: Application.fetch_env!(:sencha, :hostname),
        command: "431",
        middle: [target[:nickname] || "*"],
        trailing: "No nickname given"
      }
    )

    state
  end

  def send(state = %{target: target}, :ERR_ERRONEOUSNICKNAME, _params) do
    Sencha.User.message_send(
      self(),
      %Sencha.Message{
        prefix: Application.fetch_env!(:sencha, :hostname),
        command: "432",
        middle: [target[:nickname] || "*"],
        trailing: "Erroneous nickname"
      }
    )

    state
  end

  def send(state = %{target: target}, :ERR_NICKNAMEINUSE, _params) do
    Sencha.User.message_send(
      self(),
      %Sencha.Message{
        prefix: Application.fetch_env!(:sencha, :hostname),
        command: "433",
        middle: [target[:nickname] || "*"],
        trailing: "Nickname already in use"
      }
    )

    state
  end

  def send(state = %{target: target}, :ERR_NEEDMOREPARAMS, %{command: command}) do
    Sencha.User.message_send(
      self(),
      %Sencha.Message{
        prefix: Application.fetch_env!(:sencha, :hostname),
        command: "461",
        middle: [target[:nickname] || "*", command],
        trailing: "Not enough parameters"
      }
    )

    state
  end

  def send(state = %{target: target}, :ERR_ALREADYREGISTERED, _params) do
    Sencha.User.message_send(
      self(),
      %Sencha.Message{
        prefix: Application.fetch_env!(:sencha, :hostname),
        command: "462",
        middle: [target[:nickname] || "*"],
        trailing: "You may not re-register"
      }
    )

    state
  end

  def send(state = %{target: target}, :ERR_YOUREBANNEDCREEP, _params) do
    Sencha.User.message_send(
      self(),
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
