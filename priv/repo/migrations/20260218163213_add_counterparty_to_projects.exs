defmodule Firmowid.Repo.Migrations.AddCounterpartyToProjects do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :counterparty_id, references(:counterparties, on_delete: :nilify_all)
    end

    create index(:projects, [:counterparty_id])
  end
end
