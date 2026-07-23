# IRC user schema
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
defmodule Sencha.Repo.User do
  @moduledoc """
  IRC user schema
  """
  use Ecto.Schema

  @re_name ~r/^[a-zA-Z\[\\\]\^\_\{\|\}][a-zA-Z0-9\[\\\]\^\_\-\{\|\}]*$/
  @timestamps_opts [type: :utc_datetime]

  schema "users" do
    # SASL username
    field(:name, :binary)

    # Argon2 hash of SASL password
    field(:hash, :binary, redact: true)

    has_many(:channel, Sencha.Repo.Channel)

    timestamps()
  end

  def max_length_name(), do: 15

  @doc """
  Checks for valid/invalid ASCII nicknames on IRC

  SEE: https://www.unrealircd.org/docs/Nick_Character_Sets
  """
  def regex_name(), do: @re_name

  def changeset(struct, params \\ %{}) do
    struct
    |> Ecto.Changeset.cast(params, [:name, :hash])
    |> Ecto.Changeset.validate_required([:name, :hash])
    |> Ecto.Changeset.validate_length(:name, min: 1, max: max_length_name())
    |> Ecto.Changeset.validate_format(:name, @re_name,
      message: "is not a valid name on this server"
    )
  end
end
