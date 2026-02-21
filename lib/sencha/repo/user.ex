defmodule Sencha.Repo.User do
  use Ecto.Schema
  import Ecto.Changeset

  def max_nickname_length(), do: 15
  def max_lock_reason_length(), do: 127

  schema "users" do
    field(:nickname, :string)
    field(:password, :string, redact: true)

    field(:operator, :boolean, default: false)
    field(:operator_secret, :binary, default: <<>>, redact: true)

    field(:locked, :boolean, default: false)
    field(:locked_reason, :string)

    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:nickname, :password, :operator, :operator_secret, :locked, :locked_reason])
    |> validate_required([:nickname, :password])
    |> validate_exclusion(:nickname, ~w(Services), message: "must not impose bot nicknames")
    |> validate_length(:nickname, min: 1, max: max_nickname_length())
    |> validate_length(:locked_reason, min: 1, max: max_lock_reason_length())
    |> validate_format(
      :nickname,
      ~r/^[A-Za-z\x5b-\x60\x7b-\x7d][0-9A-Za-z\-\x5b-\x60\x7b-\x7d]*$/,
      message: "must be an RFC2812-compliant nickname"
    )
    |> unique_constraint(:nickname)
  end
end
