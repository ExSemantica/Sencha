defmodule Sencha.User.Operator do
  @moduledoc """
  Lets users escalate privileges for a specified timespan.
  """
  import Ecto.Query

  @doc """
  Checks if this user is authorized to escalate to operator privileges given
  their password, and a TOTP token.
  """
  def check_authorized(%Sencha.User.State{nickname: nickname}, password, totp) do
    case Sencha.Repo.one(
           from(u in Sencha.Repo.User, where: u.nickname == ^nickname and u.operator == ^true)
         ) do
      nil ->
        Argon2.no_user_verify()
        {:error, :not_operator}

      %Sencha.Repo.User{password: hash, operator_secret: secret} ->
        check_secret(secret, totp, Argon2.verify_pass(password, hash))
    end
  end

  defp check_secret(secret, totp, true) do
    if NimbleTOTP.valid?(secret, totp) do
      :ok
    else
      {:error, :not_operator}
    end
  end

  defp check_secret(_, _, false) do
    {:error, :invalid_password}
  end
end
