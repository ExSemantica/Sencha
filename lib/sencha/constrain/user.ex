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
  @regex ~r/^[a-zA-Z\[\\\]\^\_\{\|\}][a-zA-Z0-9\[\\\]\^\_\-\{\|\}]*$/
  @max_length_name 15

  def max_length_name(), do: @max_length_name

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
