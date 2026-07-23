# IRC channel schema
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
defmodule Sencha.Repo.Channel do
  @moduledoc """
  IRC channel schema
  """
  use Ecto.Schema

  @timestamps_opts [type: :utc_datetime]

  schema "channels" do
    # Visible channel name including its prefix
    field(:name, :binary)
    # Visible channel topic
    field(:topic, :binary)

    # SEE: https://modern.ircdocs.horse/#rpltopicwhotime-333
    field(:topic_changed, :utc_datetime)

    belongs_to(:user, Sencha.Repo.User)

    # SEE: https://modern.ircdocs.horse/#rplcreationtime-329
    # Ecto provides us with creation timestamps automatically
    timestamps()
  end

  def max_length_name(), do: 31
  def max_length_topic(), do: 127

  def changeset(struct, params \\ %{}) do
    struct
    |> Ecto.Changeset.cast(params, [:name, :topic])
    |> Ecto.Changeset.validate_required([:name, :topic])
    |> Ecto.Changeset.validate_length(:name, min: 1, max: max_length_name())
    |> Ecto.Changeset.validate_length(:topic, min: 1, max: max_length_topic())
  end
end
