defmodule Firmowid.Ash.Analysis.CounterpartyCategory do
  @moduledoc """
  Category the owner confirmed for one counterparty's income or expenses.

  Analysis applies the rule to every entry of that counterparty, including new
  ones, so the owner classifies a counterparty once. The suggestion shown at
  confirmation is kept to measure how often suggestions are accepted unchanged.
  """
  use Ash.Resource,
    domain: Firmowid.Ash.Analysis,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Analysis.IndustryTemplate
  alias Firmowid.Ash.Checks.AtLeastRole
  alias Firmowid.Ash.Resource

  require Resource

  postgres do
    table "analysis_counterparty_categories"
    repo Firmowid.Repo

    references do
      reference :organization, on_delete: :delete
    end
  end

  code_interface do
    define :list, action: :read
    define :confirm
  end

  actions do
    defaults [:read]

    create :confirm do
      description "Confirm or change the category of a counterparty's income or expenses."

      accept [
        :side,
        :counterparty_key,
        :counterparty_name,
        :category,
        :suggested_category,
        :suggestion_source
      ]

      upsert? true
      upsert_identity :unique_counterparty
      upsert_fields [:counterparty_name, :category, :updated_at]

      validate fn changeset, _context ->
        side = Ash.Changeset.get_attribute(changeset, :side)
        category = Ash.Changeset.get_attribute(changeset, :category)

        if category in IndustryTemplate.all_categories(side),
          do: :ok,
          else: {:error, field: :category, message: "is not a category of this side"}
      end
    end
  end

  policies do
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

    attribute :side, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: [:income, :expenses]]

    attribute :counterparty_key, :string, allow_nil?: false, public?: true
    attribute :counterparty_name, :string, allow_nil?: false, public?: true
    attribute :category, :atom, allow_nil?: false, public?: true
    attribute :suggested_category, :atom, public?: true

    attribute :suggestion_source, :atom,
      public?: true,
      constraints: [one_of: [:certain, :invoice_lines, :name, :learned, :default]]

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :organization, Firmowid.Ash.Core.Organization do
      allow_nil? false
    end
  end

  identities do
    identity :unique_counterparty, [:organization_id, :side, :counterparty_key]
  end
end
