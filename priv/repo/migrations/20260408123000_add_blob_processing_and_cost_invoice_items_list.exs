defmodule Firmowid.Repo.Migrations.AddBlobProcessingAndCostInvoiceItemsList do
  use Ecto.Migration

  def up do
    alter table(:blobs) do
      add :processing_target, :string, null: false, default: "none"
      add :processing_state, :string, null: false, default: "succeeded"
      add :processing_metadata, :map, null: false, default: %{}
    end

    alter table(:cost_invoices) do
      add :items_list, :jsonb, null: false, default: fragment("'[]'::jsonb")
      modify :description, :text, null: false, default: ""
    end
  end

  def down do
    alter table(:cost_invoices) do
      modify :description, :text, null: false, default: nil
      remove :items_list
    end

    alter table(:blobs) do
      remove :processing_metadata
      remove :processing_state
      remove :processing_target
    end
  end
end
