defmodule Sencha.Repo.Migrations.AddChannels do
  use Ecto.Migration

  def up do
    create table "channels" do
      add :name, :string
      add :topic, :text
      add :topic_set, :utc_datetime
      add :bans, {:array, :string}
      add :ban_exceptions, {:array, :string}
      add :operators, {:array, :string}
      add :voices, {:array, :string}
      add :other_modes, :binary

      add :user_id, :id

      timestamps()
    end
  end

  def down do
    drop table "channels"
  end
end
