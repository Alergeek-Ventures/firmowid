defmodule Firmowid.Ash.Analysis.EntryCategory do
  @moduledoc """
  Category the classifier chose for one analysis entry from its description.

  Certain signals (salaries, tax tags) and the owner's counterparty categories
  take precedence over it, so it only fills in what they leave open.
  """
  use Ash.Resource,
    domain: Firmowid.Ash.Analysis,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Analysis.IndustryTemplate
  alias Firmowid.Ash.Checks.AtLeastRole
  alias Firmowid.Ash.Checks.SystemActorRole
  alias Firmowid.Ash.Resource

  require Resource

  postgres do
    table "analysis_entry_categories"
    repo Firmowid.Repo

    references do
      reference :organization, on_delete: :delete
    end
  end

  code_interface do
    define :list, action: :read
    define :assign
  end

  actions do
    defaults [:read]

    create :assign do
      description "Store the category the classifier chose for an entry."
      accept [:entity_type, :resource_id, :category]

      upsert? true
      upsert_identity :unique_entry
      upsert_fields [:category, :updated_at]

      validate fn changeset, _context ->
        category = Ash.Changeset.get_attribute(changeset, :category)

        if category in (IndustryTemplate.all_categories(:expenses) ++
                          IndustryTemplate.all_categories(:income)),
           do: :ok,
           else: {:error, field: :category, message: "is not a template category"}
      end
    end
  end

  policies do
    bypass [{SystemActorRole, roles: [:analysis_classifier]}, action([:read, :assign])] do
      authorize_if always()
    end

    policy Firmowid.Ash.Checks.IsSystemActor do
      forbid_if always()
    end

    # The dashboard shows categories to everyone who may read the year summary.
    policy action_type(:read) do
      authorize_if {AtLeastRole, role: :invoicing}
    end

    policy action_type(:create) do
      authorize_if {AtLeastRole, role: :accountant}
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :entity_type, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: [:sales_invoice, :cost_invoice, :transaction]]

    attribute :resource_id, :uuid, allow_nil?: false, public?: true
    attribute :category, :atom, allow_nil?: false, public?: true

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :organization, Firmowid.Ash.Core.Organization do
      allow_nil? false
    end
  end

  identities do
    identity :unique_entry, [:organization_id, :entity_type, :resource_id]
  end
end
