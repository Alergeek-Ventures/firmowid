defmodule Firmowid.Ash.Timetracker.DelegationTrip do
  @moduledoc "A single departure and arrival pair from a transport expense."

  use Ash.Resource,
    otp_app: :firmowid,
    domain: Firmowid.Ash.Timetracker,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Resource

  require Resource

  postgres do
    table "delegation_trip"
    repo Firmowid.Repo

    references do
      reference :delegation_expense_transport, on_delete: :delete
    end
  end

  code_interface do
    define :read, action: :read
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      description "Create a trip belonging to a transport expense."
      primary? true

      accept [
        :delegation_expense_transport_id,
        :departure_city,
        :departure_datetime,
        :arrival_city,
        :arrival_datetime,
        :description
      ]
    end

    update :update do
      description "Update a trip belonging to a transport expense."
      primary? true

      accept [
        :departure_city,
        :departure_datetime,
        :arrival_city,
        :arrival_datetime,
        :description
      ]
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :admin) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if relates_to_actor_via([:delegation_expense_transport, :delegation, :user])
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if expr(
                     delegation_expense_transport.delegation.status == :in_progress and
                       delegation_expense_transport.delegation.user_id == ^actor(:id)
                   )
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :departure_city, :string,
      allow_nil?: false,
      default: "",
      constraints: [allow_empty?: true],
      public?: true

    attribute :departure_datetime, :utc_datetime, public?: true

    attribute :arrival_city, :string,
      allow_nil?: false,
      default: "",
      constraints: [allow_empty?: true],
      public?: true

    attribute :arrival_datetime, :utc_datetime, public?: true
    attribute :description, :string, public?: true
    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :delegation_expense_transport,
               Firmowid.Ash.Timetracker.DelegationExpenseTransport do
      allow_nil? false
      attribute_writable? true
    end

    belongs_to :organization, Firmowid.Ash.Core.Organization do
      allow_nil? false
    end
  end
end
