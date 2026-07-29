# Channel constraints
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
defmodule Sencha.Constrain.Channel do
  @moduledoc """
  Channel constraints
  """
  import Ecto.Query

  @regex ~r/^\#+[a-zA-Z\[\\\]\^\_\{\|\}][a-zA-Z0-9\[\\\]\^\_\-\{\|\}]*$/
  @max_length_name 31
  @max_length_topic 255

  def max_length_name(), do: @max_length_name
  def max_length_topic(), do: @max_length_topic
  def supported_prefixes(), do: [?\#]

  @doc """
  Inserts a `Sencha.Repo.Channel` with pre-constraints
  """
  def safe_insert(struct = %Sencha.Repo.Channel{name: name, topic: topic}) do
    cond do
      byte_size(name) > @max_length_name ->
        {:error, %{errors: [{:name, {"exceeds maximum channel name length", :PREVALIDATION}}]}}

      not is_nil(topic) and byte_size(topic) > @max_length_topic ->
        {:error, %{errors: [{:topic, {"exceeds maximum topic name length", :PREVALIDATION}}]}}

      not Regex.match?(@regex, name) ->
        unidecoded =
          Unidecode.decode(name)
          |> String.replace(" ", "_")

        {:error,
         %{
           errors: [
             {:name,
              {"has an invalid channel name (possibly valid: #{unidecoded})", :PREVALIDATION}}
           ]
         }}

      true ->
        struct
        |> Sencha.Repo.Channel.changeset()
        |> Sencha.Repo.insert()
    end
  end

  @doc """
  Updates a `Sencha.Repo.Channel` with a new topic
  """
  def safe_update_topic(%Sencha.Repo.Channel{
        name: name,
        topic: topic,
        topic_changed_by: changed_by
      }) do
    lookup =
      Sencha.Repo.one(from(c in Sencha.Repo.Channel, where: ilike(c.name, ^name), select: c))

    case lookup do
      nil ->
        {:error, %{errors: [{:name, {"does not exist", :PREVALIDATION}}]}}

      _channel when byte_size(topic) > @max_length_topic ->
        {:error, %{errors: [{:topic, {"exceeds maximum topic name length", :PREVALIDATION}}]}}

      channel ->
        %{channel | topic: topic, topic_changed: DateTime.utc_now(), topic_changed_by: changed_by}
        |> Sencha.Repo.update()

        # TODO: if :ok then send to everyone in the channel
    end
  end

  # TODO: channel modes, how and when do we send the updates to everyone?
end
