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
          Sencha.Channel.modes(?d) |> MapSet.to_list() |> to_string,
          ?a..?c
          |> Enum.reduce(MapSet.new(), &MapSet.union(&2, Sencha.Channel.modes(&1)))
          |> MapSet.to_list()
          |> to_string
        ]
      }
    )

    state
  end

  def send(state = %{target: target}, :RPL_ISUPPORT, _params) do
    supported =
      Sencha.ISupport.get()
      |> Enum.chunk_every(13)

    for features <- supported do
      Sencha.User.message_send(
        self(),
        %Sencha.Message{
          prefix: Application.fetch_env!(:sencha, :hostname),
          command: "005",
          middle: [
            target.nickname
            | features
          ],
          trailing: "are supported by this server"
        }
      )
    end

    state
  end

  def send(state = %{target: target}, :RPL_LUSERCLIENT, _params) do
    connections_num =
      length(
        :global.registered_names()
        |> Enum.filter(fn {type, _pid} -> type == Sencha.User end)
      )

    nodes_num = length([node() | Node.list()])

    Sencha.User.message_send(
      self(),
      %Sencha.Message{
        prefix: Application.fetch_env!(:sencha, :hostname),
        command: "251",
        middle: [
          target.nickname
        ],
        # TODO: invisibility
        trailing: "There are #{connections_num} users and 0 invisible on #{nodes_num} servers"
      }
    )

    state
  end

  def send(state = %{target: target}, :RPL_LUSERME, _params) do
    {:ok, connections} = Sencha.User.gather()
    connections_num = length(connections)
    nodes_num = length([node() | Node.list()])

    Sencha.User.message_send(
      self(),
      %Sencha.Message{
        prefix: Application.fetch_env!(:sencha, :hostname),
        command: "255",
        middle: [
          target.nickname
        ],
        trailing: "I have #{connections_num} clients and #{nodes_num} servers"
      }
    )

    state
  end

  def send(state = %{target: target}, :RPL_MOTD, %{line: line}) do
    Sencha.User.message_send(
      self(),
      %Sencha.Message{
        prefix: Application.fetch_env!(:sencha, :hostname),
        command: "372",
        middle: [
          target.nickname
        ],
        trailing: line
      }
    )

    state
  end

  def send(state = %{target: target}, :RPL_MOTDSTART, _params) do
    Sencha.User.message_send(
      self(),
      %Sencha.Message{
        prefix: Application.fetch_env!(:sencha, :hostname),
        command: "375",
        middle: [
          target.nickname
        ],
        trailing: "- #{Application.fetch_env!(:sencha, :hostname)} Message of the Day -"
      }
    )

    state
  end

  def send(state = %{target: target}, :RPL_ENDOFMOTD, _params) do
    Sencha.User.message_send(
      self(),
      %Sencha.Message{
        prefix: Application.fetch_env!(:sencha, :hostname),
        command: "376",
        middle: [
          target.nickname
        ],
        trailing: "End of /MOTD command"
      }
    )

    state
  end

  # ===========================================================================
  # Errors
  # ===========================================================================
  def send(state = %{target: target}, :ERR_NOMOTD, _params) do
    Sencha.User.message_send(
      self(),
      %Sencha.Message{
        prefix: Application.fetch_env!(:sencha, :hostname),
        command: "422",
        middle: [target[:nickname] || "*"],
        trailing: "MOTD file is missing"
      }
    )

    state
  end

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
