defmodule Firmowid.Repo.Migrations.AddNameAndContractDate do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :name, :string
      add :employment_date, :utc_datetime
    end
  end
end
