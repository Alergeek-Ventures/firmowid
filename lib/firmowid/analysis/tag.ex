defmodule Firmowid.Analysis.Tag do
  use Firmowid.Schema
  import Ecto.Changeset

  schema "tags" do
    field :name, :string
    field :color, :string, default: "#6B7280"

    belongs_to :organization, Firmowid.Accounts.Organization

    timestamps()
  end

  def changeset(tag, attrs) do
    tag
    |> cast(attrs, [:name, :color])
    |> validate_required([:name])
    |> put_change(:organization_id, Firmowid.Repo.get_org_id())
    |> unique_constraint([:name, :organization_id])
  end
end
