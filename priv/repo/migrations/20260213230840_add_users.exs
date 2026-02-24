defmodule Sencha.Repo.Migrations.AddUsers do
  use Ecto.Migration

  def up do
    create table "users" do
      add :nickname, :string
      add :password, :string
      add :operator, :boolean
      add :operator_secret, :binary
      add :locked, :boolean
      add :locked_reason, :string

      add :owned, {:array, :id}

      timestamps()
    end
  end

  def down do
    drop table "users"
  end
end
