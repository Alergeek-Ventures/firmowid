defmodule Firmowid.Analysis.EntityTag do
  @moduledoc false
  use Firmowid.Schema

  import Ecto.Changeset

  schema "entity_tags" do
    belongs_to :tag_definition, Firmowid.Analysis.TagDefinition

    field :entity_type, Ecto.Enum,
      values: [
        :transaction,
        :sales_invoice,
        :cost_invoice,
        :cost_invoices_transactions,
        :sales_invoices_transactions
      ]

    field :entity_id, Ecto.UUID

    belongs_to :organization, Firmowid.Accounts.Organization

    timestamps()
  end

  def changeset(tagged_item, attrs) do
    tagged_item
    |> cast(attrs, [:tag_definition_id, :entity_type, :entity_id])
    |> validate_required([:tag_definition_id, :entity_type, :entity_id])
    |> validate_inclusion(:entity_type, [
      :transaction,
      :sales_invoice,
      :cost_invoice,
      :cost_invoices_transactions,
      :sales_invoices_transactions
    ])
    |> put_change(:organization_id, Firmowid.Repo.get_org_id())
    |> unique_constraint([:entity_type, :entity_id, :tag_definition_id])
  end
end
