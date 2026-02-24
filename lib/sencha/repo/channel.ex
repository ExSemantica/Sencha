defmodule Sencha.Repo.Channel do
  use Ecto.Schema
  import Ecto.Changeset

  @default_limit 16

  def max_name_length(), do: 30
  def max_topic_length(), do: 511
  def max_bans_array_length(), do: 128
  def max_ban_exceptions_array_length(), do: 16
  def max_operators_array_length(), do: 32
  def max_voices_array_length(), do: 64

  def default_channel_limit(), do: @default_limit
  def max_channel_limit(), do: 128

  schema "users" do
    # We automatically prepend the '#' in the name
    field(:name, :string)

    field(:topic, :string, default: "")
    field(:topic_set, :utc_datetime)

    field(:limit, :integer, default: @default_limit)
    field(:other_modes, :binary, default: <<>>)

    # These are strings so we can use CIDR ranges or SASL usernames
    field(:bans, {:array, :string}, default: [])
    field(:ban_exceptions, {:array, :string}, default: [])
    field(:operators, {:array, :string}, default: [])
    field(:voices, {:array, :string}, default: [])

    # NOTE: by default we channel op the channel owner and the Services user
    belongs_to(:user, Sencha.Repo.User)

    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [
      :name,
      :limit,
      :topic,
      :topic_set,
      :bans,
      :ban_exceptions,
      :operators,
      :user,
      :other_modes
    ])
    |> validate_required([
      :name,
      :limit,
      :topic,
      :topic_set,
      :bans,
      :ban_exceptions,
      :operators,
      :user,
      :other_modes
    ])
    |> validate_number(:limit, min: 2, max: max_channel_limit())
    |> validate_length(:name, min: 1, max: max_name_length())
    |> validate_length(:topic, min: 1, max: max_topic_length())
    |> validate_length(:bans, min: 0, max: max_bans_array_length())
    |> validate_length(:ban_exceptions, min: 0, max: max_ban_exceptions_array_length())
    |> validate_length(:operators, min: 0, max: max_operators_array_length())
    |> validate_length(:voices, min: 0, max: max_voices_array_length())
    |> validate_format(
      :name,
      ~r/^[\x01-\x07\x08-\x09\x0B-\x0C\x0E-\x1F\x21-\x2B\x2D-\x39\x3B-\xFF]*$/,
      message: "must be an RFC2812-compliant channel name"
    )
    |> unique_constraint(:name)
  end
end
