defmodule Firmowid.Analysis.EntityTag.Persistence do
  @moduledoc "Persistence configuration, attributes, and relationships for entity tags."
  use Spark.Dsl.Fragment, of: Ash.Resource, data_layer: AshPostgres.DataLayer

  alias Firmowid.Analysis.TagDefinition
  alias Firmowid.Analysis.Validations.KindTagDefinitionConsistency
  alias Firmowid.Resource

  require Resource

  postgres do
    polymorphic? true
    repo Firmowid.Repo
  end

  validations do
    validate KindTagDefinitionConsistency, on: [:create]
  end

  changes do
    change fn changeset, _context ->
             Ash.Changeset.manage_relationship(
               changeset,
               :tag_definition,
               Ash.Changeset.get_attribute(changeset, :tag_definition_id),
               type: :append_and_remove
             )
           end,
           on: [:create]
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :kind, :atom,
      public?: true,
      allow_nil?: false,
      default: :project,
      constraints: [one_of: [:project, :company, :taxes, :internal]]

    attribute :resource_id, :uuid, public?: true, allow_nil?: false

    attribute :assignment_source, :atom,
      allow_nil?: false,
      default: :manual,
      constraints: [one_of: [:manual, :jev]]

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :tag_definition, TagDefinition do
      allow_nil? true
      attribute_writable? true
    end

    belongs_to :organization, Firmowid.Core.Organization do
      allow_nil? false
    end
  end
end
