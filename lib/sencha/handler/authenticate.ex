defmodule Sencha.Handler.Authenticate do
  @moduledoc """
  Performs SASL authentication
  """
  import Ecto.Query

  @doc """
  Helper for concatenating IRCv3 SASL PLAIN packets
  """
  def handle_packet(packets, "+") do
    {:ok, packets |> Enum.reverse() |> Enum.join() |> String.split("\0")}
  end

  def handle_packet(_packets, "*") do
    {:error, :aborted}
  end

  def handle_packet(packets, raw) when bit_size(raw) < 400 do
    case Base.decode64(raw) do
      {:ok, append} ->
        {:ok, [append | packets] |> Enum.reverse() |> Enum.join() |> String.split("\0")}

      :error ->
        {:error, :malformed}
    end
  end

  def handle_packet(packets, raw) when bit_size(raw) == 400 do
    case Base.decode64(raw) do
      {:ok, append} ->
        {:continue, [append | packets]}

      :error ->
        {:error, :malformed}
    end
  end

  def handle_packet(_packets, _raw) do
    {:error, :too_long}
  end

  @doc """
  After SASL, makes sure this is a valid user
  """
  def check_user([_authzid, authcid, password]) do
    # Look up the user in the database
    case Sencha.Repo.one(from(u in Sencha.Repo.User, where: u.nickname == ^authcid)) do
      nil ->
        Argon2.no_user_verify()

        {:error, :no_such_user}

      user = %Sencha.Repo.User{password: hash} ->
        if Argon2.verify_pass(password, hash) do
          check_locked(user)
        else
          {:error, :invalid_password}
        end
    end
  end

  def check_user(_malformed) do
    {:error, :malformed}
  end

  @doc """
  After user is valid, checks if the user is locked
  """
  def check_locked(user = %Sencha.Repo.User{locked: true}) do
    {:error, {:locked, user}}
  end

  def check_locked(user = %Sencha.Repo.User{locked: false}) do
    {:ok, user}
  end
end
