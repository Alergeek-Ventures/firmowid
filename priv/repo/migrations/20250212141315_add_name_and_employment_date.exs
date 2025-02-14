defmodule Firmowid.Repo.Migrations.AddNameAndEmpoymentDate do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :name, :string
      add :employment_date, :date
    end
  end
end
