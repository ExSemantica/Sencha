# Conveniences for administering a Sencha network
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
defmodule Sencha.Administration do
  @moduledoc """
  Conveniences for administering a Sencha network
  """
  require Logger
  import Ecto.Query

  def user_register(username, password) do
    case %Sencha.Repo.User{
           name: username,
           hash: Argon2.hash_pwd_salt(password)
         }
         |> Sencha.Constrain.User.safe_insert() do
      {:ok, _user} ->
        Logger.notice("User '#{username}' has been registered")

      {:error, changeset} ->
        for error <- changeset.errors do
          {_what, {name, _constraint}} = error
          Logger.warning("User '#{username}' #{name}")
        end

        :error
    end
  end

  def user_remove(username) do
    Sencha.Repo.one!(from(u in Sencha.Repo.User, where: ilike(u.name, ^username), select: u))
    |> Sencha.Repo.delete!()

    Logger.notice("User '#{username}' has been removed")
  end

  def channel_register(name, modes) do
    case %Sencha.Repo.Channel{
           name: name,
           sticky_modes: modes
         }
         |> Sencha.Constrain.Channel.safe_insert() do
      {:ok, _user} ->
        Logger.notice("Channel '#{name}' has been registered")

      {:error, changeset} ->
        for error <- changeset.errors do
          {_what, {what, _constraint}} = error
          Logger.warning("Channel '#{name}' #{what}")
        end

        :error
    end
  end

  def channel_remove(channel) do
    Sencha.Repo.one!(from(c in Sencha.Repo.Channel, where: ilike(c.name, ^channel), select: c))
    |> Sencha.Repo.delete!()

    Logger.notice("Channel '#{channel}' has been removed")
  end
end
