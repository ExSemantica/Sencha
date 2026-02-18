defmodule Sencha.Repo.Migrations.AddUsers do
  use Ecto.Migration

  def up do
    create table "users" do
      add :nickname, :string
      add :password, :string
      add :locked, :boolean
      add :locked_reason, :string

      timestamps()
    end
  end

  def down do
    drop table "users"
  end
end
