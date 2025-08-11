defmodule Firmowid.Analysis.TaggedItem do
  @moduledoc false
  use Firmowid.Schema

  import Ecto.Changeset

  schema "tagged_items" do
    belongs_to :tag, Firmowid.Analysis.Tag

    field :entity_type, :string
    field :entity_id, Ecto.UUID

    belongs_to :organization, Firmowid.Accounts.Organization

    timestamps()
  end

  def changeset(tagged_item, attrs) do
    tagged_item
    |> cast(attrs, [:tag_id, :entity_type, :entity_id])
    |> validate_required([:tag_id, :entity_type, :entity_id])
    |> validate_inclusion(:entity_type, ["transaction", "sales_invoice", "cost_invoice"])
    |> put_change(:organization_id, Firmowid.Repo.get_org_id())
    |> unique_constraint([:entity_type, :entity_id, :tag_id])
  end
end
