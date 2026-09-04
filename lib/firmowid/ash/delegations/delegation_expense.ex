defmodule Firmowid.Ash.Delegations.DelegationExpense do
  @moduledoc "A document-backed cost included in a business-trip delegation settlement."

  use Ash.Resource,
    otp_app: :firmowid,
    domain: Firmowid.Ash.Delegations,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Delegations.Changes.CreateExpenseBlob
  alias Firmowid.Ash.Delegations.DelegationExpense.Details
  alias Firmowid.Ash.Delegations.Validations.ExpenseDetailsComplete
  alias Firmowid.Ash.Delegations.Validations.ExpenseDetailsMatchKind
  alias Firmowid.Ash.Resource

  require Resource

  postgres do
    table "delegation_expenses"
    repo Firmowid.Repo
  end

  code_interface do
    define :read, action: :read
    define :complete, action: :complete
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      description "Create a document-backed expense for a delegation."
      primary? true

      accept [
        :delegation_id,
        :kind,
        :original_filename,
        :document_number,
        :expense_amount,
        :details
      ]

      argument :upload_path, :string
      argument :content_type, :string

      change CreateExpenseBlob
      validate {ExpenseDetailsMatchKind, []}
    end

    update :update do
      description "Update an expense while settling a delegation."
      primary? true
      require_atomic? false
      accept [:document_number, :expense_amount, :details]

      validate {ExpenseDetailsMatchKind, []}
    end

    update :complete do
      description "Validate and save an expense while completing its delegation."
      require_atomic? false
      accept [:document_number, :expense_amount, :details]

      validate string_length(:document_number, min: 1), message: "Uzupełnij to pole."

      validate compare(:expense_amount, greater_than: Money.new(:PLN, 0)),
        message: "musi być większa od zera"

      validate {ExpenseDetailsMatchKind, []}
      validate {ExpenseDetailsComplete, []}
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :admin) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if relates_to_actor_via([:delegation, :user])
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if expr(delegation.status == :in_progress and delegation.user_id == ^actor(:id))
    end

    policy action(:complete) do
      authorize_if expr(
                     delegation.status in [:in_progress, :complete] and
                       delegation.user_id == ^actor(:id)
                   )
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :kind, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: [:transport, :accommodation, :other]]

    attribute :original_filename, :string, allow_nil?: false, public?: true
    attribute :document_number, :string, allow_nil?: false, default: "", public?: true

    attribute :expense_amount, AshMoney.Types.Money,
      allow_nil?: false,
      public?: true,
      default: Money.new(:PLN, 0)

    attribute :details, Details, allow_nil?: false, public?: true
    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :delegation, Firmowid.Ash.Delegations.Delegation do
      allow_nil? false
      attribute_writable? true
    end

    belongs_to :blob, Firmowid.Ash.Blobs.Blob do
      description "Uploaded expense document."
      allow_nil? true
      attribute_writable? true
    end

    belongs_to :organization, Firmowid.Ash.Core.Organization do
      allow_nil? false
    end
  end
end
