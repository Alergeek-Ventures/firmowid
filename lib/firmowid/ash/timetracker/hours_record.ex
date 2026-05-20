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

  alias Firmowid.Ash.Blobs
  alias Firmowid.Ash.Resource

  require Resource

  postgres do
    table "hours_records"
    repo Firmowid.Repo
  end

  code_interface do
    define :get, get_by: [:id]
    define :by_month, args: [:user_id, :month, :year]
    define :create
  end

  actions do
    defaults [:read]

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

    read :list do
      description "List monthly hour records with optional user and period filters."
      argument :user_id, :uuid
      argument :month, :integer
      argument :year, :integer

      prepare build(filter: expr(user_id == ^arg(:user_id))) do
        where present(:user_id)
      end

      prepare build(filter: expr(month == ^arg(:month))) do
        where present(:month)
      end

      prepare build(filter: expr(year == ^arg(:year))) do
        where present(:year)
      end
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
        upload_path = Ash.Changeset.get_argument(changeset, :upload_path)
        upload_filename = Ash.Changeset.get_argument(changeset, :upload_filename)

        case Blobs.create_blob(
               upload_path,
               "binary/octet-stream",
               upload_filename,
               tenant: context.tenant,
               actor: context.actor
             ) do
          {:ok, blob} ->
            Ash.Changeset.force_change_attribute(changeset, :blob_id, blob.id)

          {:error, reason} ->
            Ash.Changeset.add_error(changeset, reason)
        end
      end
    end
  end

  policies do
    policy Firmowid.Ash.Checks.IsSystemActor do
      forbid_if always()
    end

    policy action_type(:read) do
      authorize_if relates_to_actor_via(:user)
    end

    policy action_type(:create) do
      authorize_if relating_to_actor(:user)
    end

    # :invoicing and :accountant have no access to hours records (personal payroll data)
    # No matching policies = forbidden (default Ash behavior with authorize :by_default)
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

    belongs_to :blob, Firmowid.Ash.Blobs.Blob do
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
