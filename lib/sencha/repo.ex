defmodule Sencha.Repo do
  @moduledoc """
  Local test/evaluation repository with SQLite
  """
  use Ecto.Repo,
    otp_app: :sencha,
    adapter: Ecto.Adapters.SQLite3

  @doc """
  Add a user without operator privileges
  """
  def add_regular(username, password) do
    __MODULE__.insert(%__MODULE__.User{
      nickname: username,
      password: Argon2.hash_pwd_salt(password),
      operator: false
    })
  end

  @doc """
  Add a user with operator privileges.

  Doing this will register you a TOTP secret you can use to do OPER commands.
  """
  def add_operator(username, password) do
    secret = NimbleTOTP.secret()

    user = %__MODULE__.User{
      nickname: username,
      password: Argon2.hash_pwd_salt(password),
      operator: true,
      operator_secret: secret
    }

    case __MODULE__.insert(user) do
      {:ok, _} ->
        NimbleTOTP.otpauth_uri("Sencha:#{username}", secret)
        |> EQRCode.encode()
        |> EQRCode.render()
    end
  end


end
