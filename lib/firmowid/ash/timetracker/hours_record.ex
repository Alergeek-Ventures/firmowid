defmodule Firmowid.Ash.Timetracker.HoursRecord do
  @moduledoc """
  Ash resource wrapping the existing `hours_records` table.

  Attribute multitenancy via `organization_id`. Stores the number of hours
  worked by a user in a given month/year, with an attached blob (uploaded
  hours record document).
  """
  use Ash.Resource,
    domain: Firmowid.Ash.Timetracker,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Resource

  require Resource

  postgres do
    table("hours_records")
    repo(Firmowid.Repo)
    migrate?(false)
  end

  multitenancy do
    strategy(:attribute)
    attribute(:organization_id)
  end

  attributes do
    uuid_v7_primary_key(:id)

    attribute :month, :integer do
      public?(true)
      allow_nil?(false)
      constraints(min: 1, max: 12)
    end

    attribute :year, :integer do
      public?(true)
      allow_nil?(false)
      constraints(min: 1900)
    end

    attribute :number_of_hours, :integer do
      public?(true)
      allow_nil?(false)
      constraints(min: 1)
    end

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :user, Firmowid.Ash.Core.User do
      allow_nil?(false)
      attribute_writable?(true)
    end

    belongs_to :blob, Firmowid.Ash.Core.Blob do
      allow_nil?(false)
      attribute_writable?(true)
    end

    belongs_to :organization, Firmowid.Ash.Core.Organization do
      allow_nil?(false)
    end
  end

  identities do
    identity(:unique_month_year_user, [:month, :year, :user_id, :organization_id])
  end

  actions do
    defaults([:read, :destroy, create: :*, update: :*])
  end

  policies do
    bypass actor_attribute_equals(:role, :admin) do
      authorize_if(always())
    end

    policy action_type(:read) do
      authorize_if(always())
    end

    policy [action_type([:create, :update, :destroy]), actor_attribute_equals(:role, :employee)] do
      authorize_if(relates_to_actor_via(:user))
    end
  end
end
