defmodule Firmowid.Repo.Migrations.AddNameAndContractDate do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :name, :string
      add :employment_date, :date
    end
  end
end
