defmodule Sencha.Repo.Migrations.AddChannels do
  use Ecto.Migration

  def up do
    create table "channels" do
      add :name, :string
      add :key, :string
      add :topic, :text
      add :locked_reason, :string
      add :topic_set, :utc_datetime
      add :topic_set_by, :string
      add :bans, {:array, :string}
      add :ban_exceptions, {:array, :string}
      add :operators, {:array, :string}
      add :voices, {:array, :string}
      add :invitation_masks, {:array, :string}
      add :other_modes, :binary
      add :limit, :integer

      add :user_id, :id

      timestamps()
    end
  end

  def down do
    drop table "channels"
  end
end
