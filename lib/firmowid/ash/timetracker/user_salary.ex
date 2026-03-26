defmodule Firmowid.Ash.Timetracker.UserSalary do
  @moduledoc """
  Ash resource wrapping the existing `user_salaries` table.

  Attribute multitenancy via `organization_id`. Supports CRUD plus a soft-delete
  `retire` action that sets `deleted_at`. The partial unique index
  `user_salaries_active_unique_index` ensures only one active (non-retired)
  salary per user per organization.
  """
  use Ash.Resource,
    domain: Firmowid.Ash.Timetracker,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Resource

  require Resource

  postgres do
    table("user_salaries")
    repo(Firmowid.Repo)
    migrate?(false)
  end

  multitenancy do
    strategy(:attribute)
    attribute(:organization_id)
  end

  attributes do
    uuid_v7_primary_key(:id)

    attribute :hourly_rate, :decimal do
      public?(true)
      allow_nil?(false)
      constraints(min: 0)
    end

    attribute(:deleted_at, :date, public?: true)

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :user, Firmowid.Ash.Core.User do
      allow_nil?(false)
      attribute_writable?(true)
    end

    belongs_to :organization, Firmowid.Ash.Core.Organization do
      allow_nil?(false)
    end
  end

  identities do
    identity :active_user_salary, [:user_id, :organization_id] do
      nils_distinct?(false)
      where(expr(is_nil(deleted_at)))
      message("User already has an active salary record")
    end
  end

  actions do
    defaults([:read, :destroy, create: :*, update: :*])

    update :retire do
      accept([])
      change(set_attribute(:deleted_at, &Date.utc_today/0))
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :admin) do
      authorize_if(always())
    end

    policy action_type(:read) do
      authorize_if(always())
    end
  end
end
