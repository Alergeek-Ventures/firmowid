defmodule Firmowid.Ash.Timetracker.Session do
  @moduledoc """
  Ash resource wrapping the existing `sessions` table.

  Attribute multitenancy via `organization_id`. During migration this is
  read-only — writes still go through `Firmowid.Timetracker` context.
  """
  use Ash.Resource,
    domain: Firmowid.Ash.Timetracker,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Resource

  require Resource

  postgres do
    table("sessions")
    repo(Firmowid.Repo)
    migrate?(false)
  end

  multitenancy do
    strategy(:attribute)
    attribute(:organization_id)
  end

  attributes do
    uuid_v7_primary_key(:id)

    attribute(:title, :string, public?: true, allow_nil?: false)
    attribute(:start_datetime, :utc_datetime, public?: true, allow_nil?: false)
    attribute(:end_datetime, :utc_datetime, public?: true)
    attribute(:is_remote, :boolean, public?: true, default: false)

    Resource.firmowid_timestamps()
  end

  calculations do
    calculate :duration,
              :integer,
              expr(
                if is_nil(end_datetime) do
                  fragment("EXTRACT(EPOCH FROM (NOW() - ?))::integer", start_datetime)
                else
                  fragment("EXTRACT(EPOCH FROM (? - ?))::integer", end_datetime, start_datetime)
                end
              ) do
      public?(true)
    end
  end

  relationships do
    belongs_to :user, Firmowid.Ash.Core.User do
      allow_nil?(false)
      attribute_writable?(true)
    end

    belongs_to :project, Firmowid.Ash.Timetracker.Project do
      allow_nil?(true)
      attribute_writable?(true)
    end

    belongs_to :organization, Firmowid.Ash.Core.Organization do
      allow_nil?(false)
    end
  end

  actions do
    defaults([:read])
  end

  policies do
    bypass actor_attribute_equals(:role, :admin) do
      authorize_if(always())
    end

    policy [action_type(:read), actor_attribute_equals(:role, :employee)] do
      authorize_if(relates_to_actor_via(:user))
    end
  end
end
