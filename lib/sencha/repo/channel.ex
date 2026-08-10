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
    field(:name, :string)
    # Visible channel topic
    field(:topic, :string)
    # Who changed the topic? The user might've been deleted so don't reference
    field(:topic_changed_by, :string)

    # SEE: https://modern.ircdocs.horse/#rpltopicwhotime-333
    field(:topic_changed, :utc_datetime)

    # Channel modes that stay after the operator(s) leave
    field(:sticky_modes, {:array, :string})

    # SEE: https://modern.ircdocs.horse/#rplcreationtime-329
    # Ecto provides us with creation timestamps automatically
    timestamps()
  end

  def changeset(struct, params \\ %{}) do
    struct
    |> Ecto.Changeset.cast(params, [
      :name,
      :topic,
      :topic_changed_by,
      :topic_changed,
      :sticky_modes
    ])
    |> Ecto.Changeset.unique_constraint([:name], message: "is already taken")
    |> Ecto.Changeset.validate_required([:name])
  end
end
