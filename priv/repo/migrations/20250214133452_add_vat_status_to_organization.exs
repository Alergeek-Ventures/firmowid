defmodule Firmowid.Repo.Migrations.AddVatStatusToOrganization do
  use Ecto.Migration

  def change do
    alter table(:organizations) do
      add :is_vat_payer, :boolean, default: true
    end
  end
end
