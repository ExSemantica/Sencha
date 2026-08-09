# User constraints
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
defmodule Sencha.Constrain.User do
  @moduledoc """
  User constraints
  """
  # Nickname regex
  @regex ~r/^[a-zA-Z\[\\\]\^\_\{\|\}][a-zA-Z0-9\[\\\]\^\_\-\{\|\}]*$/

  # Username regex like a UNIX login
  @regex_ident ~r/^[a-zA-Z][a-zA-Z0-9\.\_\-]*$/

  # Username regex like a UNIX GECOS field
  @regex_gecos ~r/^[^\x00\r\n]*$/

  @max_length_name 15
  @max_length_ident 15
  @max_length_gecos 127
  @max_length_host 127

  def max_length_name(), do: @max_length_name
  def max_length_ident(), do: @max_length_ident
  def max_length_gecos(), do: @max_length_gecos
  def max_length_host(), do: @max_length_host

  @doc """
  Check a nickname
  """
  def check_name?(name) do
    cond do
      byte_size(name) > @max_length_name -> false
      not Regex.match?(@regex, name) -> false
      true -> true
    end
  end

  @doc """
  Check an ident
  """
  def check_ident?(ident) do
    cond do
      byte_size(ident) > @max_length_ident -> false
      not Regex.match?(@regex_ident, ident) -> false
      true -> true
    end
  end

  @doc """
  Check a real name
  """
  def check_gecos?(gecos) do
    cond do
      byte_size(gecos) > @max_length_gecos -> false
      not Regex.match?(@regex_gecos, gecos) -> false
      true -> true
    end
  end

  @doc """
  Inserts a `Sencha.Repo.User` with pre-constraints
  """
  def safe_insert(struct = %Sencha.Repo.User{name: name}) do
    cond do
      byte_size(name) > @max_length_name ->
        {:error, %{errors: [{:name, {"exceeds maximum account name length", :PREVALIDATION}}]}}

      not Regex.match?(@regex, name) ->
        unidecoded =
          Unidecode.decode(name)
          |> String.replace(" ", "_")

        {:error,
         %{
           errors: [
             {:name, {"has an invalid user name (possibly valid: #{unidecoded})", :PREVALIDATION}}
           ]
         }}

      true ->
        struct
        |> Sencha.Repo.User.changeset()
        |> Sencha.Repo.insert()
    end
  end
end
