defmodule Sencha.Repo.Channel do
  use Ecto.Schema
  import Ecto.Changeset

  def max_name_length(), do: 30
  def max_topic_length(), do: 511
  def max_locked_reason_length(), do: 127
  def max_bans_array_length(), do: 128
  def max_ban_exceptions_array_length(), do: 32
  def max_invitation_masks_array_length(), do: 32
  def max_operators_array_length(), do: 32
  def max_voices_array_length(), do: 64

  def max_key_size(), do: 128

  def max_channel_limit(), do: 128

  schema "channels" do
    field(:name, :string)

    field(:topic, :string, default: "")
    field(:key, :string, default: "")
    field(:locked_reason, :string, default: "")
    field(:topic_set, :utc_datetime)
    field(:topic_set_by, :string)

    field(:limit, :integer, default: 0)
    field(:other_modes, :binary, default: <<0::integer-size(64)-little>>)

    # These are strings so we can use CIDR ranges or SASL usernames
    field(:bans, {:array, :string}, default: [])
    field(:ban_exceptions, {:array, :string}, default: [])
    field(:operators, {:array, :string}, default: [])
    field(:voices, {:array, :string}, default: [])
    field(:invitation_masks, {:array, :string}, default: [])

    # NOTE: by default we channel op the channel owner and the Services user
    belongs_to(:user, Sencha.Repo.User)

    timestamps()
  end

  def changeset(channel, attrs) do
    channel
    |> cast(attrs, [
      :name,
      :key,
      :locked_reason,
      :limit,
      :topic,
      :topic_set,
      :topic_set_by,
      :bans,
      :ban_exceptions,
      :operators,
      :user,
      :other_modes,
      :invitation_masks
    ])
    |> validate_required([
      :name,
      :key,
      :locked_reason,
      :limit,
      :topic,
      :topic_set,
      :topic_set_by,
      :bans,
      :ban_exceptions,
      :operators,
      :user,
      :other_modes,
      :invitation_masks
    ])
    |> validate_number(:limit, min: 0, max: max_channel_limit())
    |> validate_length(:name, min: 1, max: max_name_length())
    |> validate_length(:topic, min: 1, max: max_topic_length())
    |> validate_length(:locked_reason, min: 0, max: max_locked_reason_length())
    |> validate_length(:bans, min: 0, max: max_bans_array_length())
    |> validate_length(:ban_exceptions, min: 0, max: max_ban_exceptions_array_length())
    |> validate_length(:operators, min: 0, max: max_operators_array_length())
    |> validate_length(:voices, min: 0, max: max_voices_array_length())
    |> validate_length(:invitation_masks, min: 0, max: max_invitation_masks_array_length())
    |> validate_length(:key, min: 0, max: max_key_size())
    |> validate_format(
      :name,
      ~r/^[\x01-\x07\x08-\x09\x0B-\x0C\x0E-\x1F\x21-\x2B\x2D-\x39\x3B-\xFF]*$/,
      message: "must be an RFC2812-compliant channel name"
    )
    |> unique_constraint(:name)
  end
end
