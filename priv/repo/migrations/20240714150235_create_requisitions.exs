defmodule Firmowid.Repo.Migrations.CreateRequisitions do
  use Ecto.Migration

  def change do
    create table(:requisitions) do
      add :requisition_id, :string
      add :status, :string

      timestamps(type: :utc_datetime)
    end
  end
end
