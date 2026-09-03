# credo:disable-for-this-file Credo.Check.Design.DuplicatedCode
# This resource-local policy intentionally repeats the authorization expression
# because the relationship path to the delegation is specific to trips.
defmodule Firmowid.Ash.Delegations.DelegationTrip do
  @moduledoc "A single departure and arrival pair from a transport expense."

  use Ash.Resource,
    otp_app: :firmowid,
    domain: Firmowid.Ash.Delegations,
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
    define :complete, action: :complete
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

      validate compare(:arrival_datetime, greater_than_or_equal_to: :departure_datetime),
        message: "musi być po lub o tej samej godzinie co wyjazd"
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

      validate compare(:arrival_datetime, greater_than_or_equal_to: :departure_datetime),
        message: "musi być po lub o tej samej godzinie co wyjazd"
    end

    update :complete do
      description "Validate and save a trip while completing its delegation."
      require_atomic? false

      accept [
        :departure_city,
        :departure_datetime,
        :arrival_city,
        :arrival_datetime,
        :description
      ]

      validate string_length(:departure_city, min: 1), message: "Uzupełnij to pole."
      validate present(:departure_datetime), message: "Uzupełnij datę i godzinę."
      validate string_length(:arrival_city, min: 1), message: "Uzupełnij to pole."
      validate present(:arrival_datetime), message: "Uzupełnij datę i godzinę."

      validate compare(:arrival_datetime, greater_than_or_equal_to: :departure_datetime),
        message: "musi być po lub o tej samej godzinie co wyjazd"
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :admin) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if relates_to_actor_via([:delegation_expense_transport, :delegation, :user])
    end

    policy action_type([:create, :destroy]) do
      authorize_if expr(
                     delegation_expense_transport.delegation.status == :in_progress and
                       delegation_expense_transport.delegation.user_id == ^actor(:id)
                   )
    end

    policy action(:update) do
      authorize_if expr(
                     delegation_expense_transport.delegation.status == :in_progress and
                       delegation_expense_transport.delegation.user_id == ^actor(:id)
                   )
    end

    policy action(:complete) do
      authorize_if expr(
                     delegation_expense_transport.delegation.status in [:in_progress, :complete] and
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
               Firmowid.Ash.Delegations.DelegationExpenseTransport do
      allow_nil? false
      attribute_writable? true
    end

    belongs_to :organization, Firmowid.Ash.Core.Organization do
      allow_nil? false
    end
  end
end
