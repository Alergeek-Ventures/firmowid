defmodule Firmowid.Ash.Timetracker.DelegationExpenseTransport do
  @moduledoc "Transport expense attached to a delegation."

  use Ash.Resource,
    otp_app: :firmowid,
    domain: Firmowid.Ash.Timetracker,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Resource
  alias Firmowid.Ash.Timetracker.DelegationTrip

  require Resource

  postgres do
    table "delegation_expense_transport"
    repo Firmowid.Repo

    custom_statements do
      statement :require_trip do
        after_tables ["delegation_trip"]
        code? true

        up """
        execute(~S|CREATE FUNCTION require_transport_expense_trip() RETURNS trigger AS $$
        DECLARE
          transport_expense_id uuid;
        BEGIN
          transport_expense_id := CASE
            WHEN TG_TABLE_NAME = 'delegation_expense_transport' THEN NEW.id
            ELSE OLD.delegation_expense_transport_id
          END;

          IF EXISTS (SELECT 1 FROM delegation_expense_transport WHERE id = transport_expense_id)
             AND NOT EXISTS (
               SELECT 1 FROM delegation_trip
               WHERE delegation_expense_transport_id = transport_expense_id
             ) THEN
            RAISE EXCEPTION 'transport expense must contain at least one trip';
          END IF;

          RETURN NULL;
        END;
        $$ LANGUAGE plpgsql;|)

        execute(~S|INSERT INTO delegation_trip (
          id,
          departure_city,
          arrival_city,
          delegation_expense_transport_id,
          organization_id,
          inserted_at,
          updated_at
        )
        SELECT
          uuid_generate_v7(),
          '',
          '',
          transport_expense.id,
          transport_expense.organization_id,
          NOW() AT TIME ZONE 'utc',
          NOW() AT TIME ZONE 'utc'
        FROM delegation_expense_transport AS transport_expense
        WHERE NOT EXISTS (
          SELECT 1
          FROM delegation_trip
          WHERE delegation_trip.delegation_expense_transport_id = transport_expense.id
        );|)

        execute(~S|CREATE CONSTRAINT TRIGGER delegation_expense_transport_requires_trip
        AFTER INSERT ON delegation_expense_transport
        DEFERRABLE INITIALLY DEFERRED
        FOR EACH ROW EXECUTE FUNCTION require_transport_expense_trip();|)

        execute(~S|CREATE CONSTRAINT TRIGGER delegation_trip_requires_transport_expense_sibling
        AFTER DELETE ON delegation_trip
        DEFERRABLE INITIALLY DEFERRED
        FOR EACH ROW EXECUTE FUNCTION require_transport_expense_trip();|)
        """

        down """
        execute("DROP TRIGGER delegation_trip_requires_transport_expense_sibling ON delegation_trip")
        execute("DROP TRIGGER delegation_expense_transport_requires_trip ON delegation_expense_transport")
        execute("DROP FUNCTION require_transport_expense_trip()")
        """
      end

      statement :fix_require_trip_trigger do
        after_tables ["delegation_trip"]
        code? true

        up """
        execute(~S|CREATE OR REPLACE FUNCTION require_transport_expense_trip() RETURNS trigger AS $$
        DECLARE
          transport_expense_id uuid;
        BEGIN
          transport_expense_id := CASE
            WHEN TG_OP = 'INSERT' THEN (to_jsonb(NEW) ->> 'id')::uuid
            ELSE (to_jsonb(OLD) ->> 'delegation_expense_transport_id')::uuid
          END;

          IF EXISTS (SELECT 1 FROM delegation_expense_transport WHERE id = transport_expense_id)
             AND NOT EXISTS (
               SELECT 1 FROM delegation_trip
               WHERE delegation_expense_transport_id = transport_expense_id
             ) THEN
            RAISE EXCEPTION 'transport expense must contain at least one trip';
          END IF;

          RETURN NULL;
        END;
        $$ LANGUAGE plpgsql;|)
        """

        down """
        execute(~S|CREATE OR REPLACE FUNCTION require_transport_expense_trip() RETURNS trigger AS $$
        DECLARE
          transport_expense_id uuid;
        BEGIN
          transport_expense_id := CASE
            WHEN TG_TABLE_NAME = 'delegation_expense_transport' THEN NEW.id
            ELSE OLD.delegation_expense_transport_id
          END;

          IF EXISTS (SELECT 1 FROM delegation_expense_transport WHERE id = transport_expense_id)
             AND NOT EXISTS (
               SELECT 1 FROM delegation_trip
               WHERE delegation_expense_transport_id = transport_expense_id
             ) THEN
            RAISE EXCEPTION 'transport expense must contain at least one trip';
          END IF;

          RETURN NULL;
        END;
        $$ LANGUAGE plpgsql;|)
        """
      end
    end
  end

  code_interface do
    define :read, action: :read
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      description "Create a transport expense for a delegation."
      primary? true

      accept [
        :delegation_id,
        :original_filename,
        :document_number,
        :expense_amount,
        :transport_type,
        :description
      ]

      change after_action(fn _changeset, expense, context ->
               case Ash.create(
                      DelegationTrip,
                      %{
                        departure_city: "",
                        arrival_city: "",
                        delegation_expense_transport_id: expense.id
                      },
                      actor: context.actor,
                      tenant: context.tenant
                    ) do
                 {:ok, _trip} -> {:ok, expense}
                 {:error, _reason} = error -> error
               end
             end)
    end

    update :update do
      description "Update a transport expense while settling a delegation."
      primary? true
      accept [:document_number, :expense_amount, :transport_type, :description]
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
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :original_filename, :string, allow_nil?: false, public?: true
    attribute :document_number, :string, allow_nil?: false, default: "", public?: true

    attribute :expense_amount, AshMoney.Types.Money,
      allow_nil?: false,
      public?: true,
      default: Money.new(:PLN, 0)

    attribute :transport_type, :atom,
      allow_nil?: false,
      default: :other,
      public?: true,
      constraints: [one_of: [:railway, :airplane, :bus, :other]]

    attribute :description, :string, public?: true

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :delegation, Firmowid.Ash.Timetracker.Delegation do
      allow_nil? false
      attribute_writable? true
    end

    has_many :trips, DelegationTrip

    belongs_to :organization, Firmowid.Ash.Core.Organization do
      allow_nil? false
    end
  end
end
