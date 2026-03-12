defmodule Firmowid.Analysis.EntityTag do
  @moduledoc """
  Polymorphic join between tag definitions and taggable entities
  (transactions, sales invoices, cost invoices).

  Each entity tag has a `kind`:

    * `:project` — references a user-created `TagDefinition` (requires `tag_definition_id`)
    * `:company` — built-in "firma" category (no `tag_definition_id`)
    * `:internal` — built-in "transakcja wewnętrzna" category (no `tag_definition_id`)

  Categories are mutually exclusive per entity: an entity is either tagged with
  one or more project tags, OR marked as company, OR marked as internal.
  This is enforced by a database trigger.
  """
  use Firmowid.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "entity_tags" do
    field :kind, Ecto.Enum,
      values: [:project, :company, :internal],
      default: :project

    belongs_to :tag_definition, Firmowid.Analysis.TagDefinition

    field :entity_type, Ecto.Enum, values: [:transaction, :sales_invoice, :cost_invoice]

    field :entity_id, Ecto.UUID

    belongs_to :organization, Firmowid.Accounts.Organization

    timestamps()
  end

  @doc """
  Changeset for project tags (requires `tag_definition_id`).
  """
  def changeset(entity_tag, attrs) do
    entity_tag
    |> cast(attrs, [:kind, :tag_definition_id, :entity_type, :entity_id])
    |> validate_required([:kind, :entity_type, :entity_id])
    |> validate_kind_tag_definition_consistency()
    |> put_change(:organization_id, Firmowid.Repo.get_org_id())
    |> unique_constraint([:entity_type, :entity_id, :tag_definition_id],
      name: :entity_tags_project_unique
    )
    |> unique_constraint([:entity_type, :entity_id, :kind],
      name: :entity_tags_builtin_kind_unique
    )
  end

  defp validate_kind_tag_definition_consistency(changeset) do
    kind = get_field(changeset, :kind)
    tag_def_id = get_field(changeset, :tag_definition_id)

    cond do
      kind == :project and is_nil(tag_def_id) ->
        add_error(changeset, :tag_definition_id, "is required for project tags")

      kind != :project and not is_nil(tag_def_id) ->
        add_error(changeset, :tag_definition_id, "must be empty for built-in tag kinds")

      true ->
        changeset
    end
  end
end
