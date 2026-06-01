defmodule Firmowid.Ash.Payroll.UserEmploymentContract do
  @moduledoc "Ash resource representing a user's employment contract."
  use Ash.Resource,
    otp_app: :firmowid,
    domain: Firmowid.Ash.Payroll,
    authorizers: [Ash.Policy.Authorizer],
    data_layer: AshPostgres.DataLayer,
    primary_read_warning?: false

  alias Firmowid.Ash.Checks.SystemActorRole
  alias Firmowid.Ash.Resource

  require Resource

  postgres do
    table "user_employment_contracts"
    repo Firmowid.Repo
  end

  actions do
    defaults [:destroy]

    read :get_by_id do
      description "Returns an employment contract given its id."
      argument :id, :uuid
      primary? true
      get? true

      prepare build(filter: expr(id == ^arg(:id))) do
        where present(:id)
      end
    end

    read :read do
      description "Returns all employment contracts given user_id."

      argument :user_id, :uuid

      prepare build(filter: expr(user_id == ^arg(:user_id))) do
        where present(:user_id)
      end
    end

    create :create do
      description "Create an employment contract record for a user."
      primary? true
      accept [:worker_full_name, :starts_at, :salary, :user_id, :blob_id]

      change Firmowid.Ash.Payroll.Changes.CreateSalary
    end
  end

  policies do
    policy action_type(:create) do
      authorize_if {SystemActorRole, roles: [:employment_contract_processor]}
      forbid_if always()
    end

    policy action_type(:read) do
      authorize_if actor_attribute_equals(:role, :admin)
      forbid_if always()
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :worker_full_name, :string, allow_nil?: false
    attribute :starts_at, :date, allow_nil?: false
    attribute :salary, AshMoney.Types.Money, allow_nil?: false

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :user, Firmowid.Ash.Core.User do
      allow_nil? false
      attribute_writable? true
    end

    belongs_to :organization, Firmowid.Ash.Core.Organization do
      allow_nil? false
    end

    belongs_to :blob, Firmowid.Ash.Blobs.Blob do
      allow_nil? false
      attribute_writable? true
    end
  end

  identities do
    identity :unique_contract_per_user_org, [:user_id, :organization_id, :starts_at] do
      message "User already has an employment contract with the same start date"
    end

    identity :unique_blob, [:blob_id] do
      message "Blob is already associated with another employment contract"
    end
  end
end
