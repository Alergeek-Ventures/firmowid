defmodule Firmowid.Ash.Analysis.EntityTag.Persistence do
  @moduledoc "Persistence configuration, attributes, and relationships for entity tags."
  use Spark.Dsl.Fragment, of: Ash.Resource, data_layer: AshPostgres.DataLayer

  alias Firmowid.Ash.Analysis.TagDefinition
  alias Firmowid.Ash.Analysis.Validations.KindTagDefinitionConsistency
  alias Firmowid.Ash.Resource

  require Resource

  postgres do
    polymorphic? true
    repo Firmowid.Repo
  end

  validations do
    validate KindTagDefinitionConsistency, on: [:create]
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
      constraints: [one_of: [:project, :company, :internal]]

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

    belongs_to :organization, Firmowid.Ash.Core.Organization do
      allow_nil? false
    end
  end
end
