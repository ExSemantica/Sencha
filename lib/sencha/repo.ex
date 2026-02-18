defmodule Sencha.Repo do
  @moduledoc """
  Local test/evaluation repository with SQLite
  """
  use Ecto.Repo,
    otp_app: :sencha,
    adapter: Ecto.Adapters.SQLite3
end
