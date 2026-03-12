defmodule Firmowid.Analysis.TagDefinition do
  @moduledoc "User-created project tag with a name and color."
  use Firmowid.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "tag_definitions" do
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
    |> unique_constraint([:name, :organization_id], name: :tags_organization_id_name_index)
  end
end
