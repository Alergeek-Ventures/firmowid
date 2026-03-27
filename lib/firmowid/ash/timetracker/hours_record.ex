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
    table "hours_records"
    repo(Firmowid.Repo)
    migrate?(false)
  end

  code_interface do
    define :get, get_by: [:id]
    define :by_month, args: [:user_id, :month, :year]
    define :create
    define :destroy
    define :month_hours_records, args: [:month, :year]
  end

  actions do
    defaults [:read, :destroy, update: :*]

    # ── Read actions ──────────────────────────────────────────────────

    read :get do
      description "Get a single hours record by ID with user preloaded."
      get? true

      prepare build(load: [:user])
    end

    read :by_month do
      description "Get the hours record for a user in a specific month/year."
      get? true

      argument :user_id, :uuid, allow_nil?: false
      argument :month, :integer, allow_nil?: false
      argument :year, :integer, allow_nil?: false

      filter expr(user_id == ^arg(:user_id) and month == ^arg(:month) and year == ^arg(:year))
    end

    # ── Write actions ─────────────────────────────────────────────────

    create :create do
      description "Create an hours record with blob upload. The blob is created from the uploaded file."
      accept [:month, :year, :number_of_hours, :user_id]

      argument :upload_path, :string do
        allow_nil? false
        description "Temporary file path of the uploaded document."
      end

      argument :upload_filename, :string do
        allow_nil? false
        description "Original filename of the uploaded document."
      end

      change fn changeset, context ->
        Ash.Changeset.after_action(changeset, fn _changeset, record ->
          upload_path = changeset.arguments.upload_path
          upload_filename = changeset.arguments.upload_filename

          case Firmowid.Blobs.create_blob(upload_path, "binary/octet-stream", upload_filename) do
            {:ok, blob} ->
              record
              |> Ash.Changeset.for_update(:update, %{blob_id: blob.id},
                actor: context.actor,
                tenant: context.tenant
              )
              |> Ash.update()

            {:error, reason} ->
              {:error, reason}
          end
        end)
      end
    end

    # ── Generic actions ───────────────────────────────────────────────

    action :month_hours_records, {:array, :map} do
      description "All users with their hours records for a given month/year."

      argument :month, :integer, allow_nil?: false
      argument :year, :integer, allow_nil?: false

      run fn input, _context ->
        import Ecto.Query

        %{month: month, year: year} = input.arguments

        # TODO: replace raw Ecto with Ash reads when cross-domain joins
        # (User × HoursRecord) are supported — requires migrating Accounts to Ash.
        results =
          Firmowid.Repo.all(
            from(u in Firmowid.Accounts.User,
              left_join: hr in Firmowid.Ash.Timetracker.HoursRecord,
              on: u.id == hr.user_id and hr.month == ^month and hr.year == ^year,
              order_by: [u.name, u.email],
              select: %{user: u, hours_record: hr}
            )
          )

        {:ok, results}
      end
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :admin) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if always()
    end

    policy [action_type(:create), actor_attribute_equals(:role, :employee)] do
      authorize_if Firmowid.Ash.Timetracker.Checks.OwnsResource
    end

    policy [
      action_type([:update, :destroy]),
      actor_attribute_equals(:role, :employee)
    ] do
      authorize_if relates_to_actor_via(:user)
    end

    policy [action_type(:action), actor_attribute_equals(:role, :employee)] do
      authorize_if always()
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :month, :integer do
      public? true
      allow_nil? false
      constraints min: 1, max: 12
    end

    attribute :year, :integer do
      public? true
      allow_nil? false
      constraints min: 1900
    end

    attribute :number_of_hours, :integer do
      public? true
      allow_nil? false
      constraints min: 1
    end

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :user, Firmowid.Ash.Core.User do
      allow_nil? false
      attribute_writable? true
    end

    belongs_to :blob, Firmowid.Ash.Core.Blob do
      allow_nil? false
      attribute_writable? true
    end

    belongs_to :organization, Firmowid.Ash.Core.Organization do
      allow_nil? false
    end
  end

  identities do
    identity :unique_month_year_user, [:month, :year, :user_id, :organization_id]
  end
end
