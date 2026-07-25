# K-Line schema
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
defmodule Sencha.Repo.KLine do
  @moduledoc """
  K-Line schema
  """
  use Ecto.Schema

  @timestamps_opts [type: :utc_datetime]

  schema "klines" do
    # CIDR range
    # For efficiency's sake we will not use hostmasks
    field(:cidr, :string)

    # A reason that the K-Line is in place
    field(:reason, :string)

    timestamps()
  end

  def max_length_reason(), do: 127

  def changeset(struct, params \\ %{}) do
    struct
    |> Ecto.Changeset.cast(params, [:cidr, :reason])
    |> Ecto.Changeset.validate_required([:cidr, :reason])
    |> Ecto.Changeset.validate_length(:reason, max: max_length_reason())
    |> Ecto.Changeset.validate_change(:cidr, fn :cidr, cidr ->
      case InetCidr.parse_cidr(cidr) do
        {:ok, _cidr} -> []
        {:error, _error} -> [cidr: "is not a properly-formatted CIDR block"]
      end
    end)
  end
end
