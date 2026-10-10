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
  alias Firmowid.Ash.Core.User
  alias Firmowid.Ash.Resource
  alias Firmowid.Ash.Timetracker.Validations.PendingHoursRecordChange

  require Resource

  postgres do
    table "hours_records"
    repo Firmowid.Repo
    identity_wheres_to_sql unique_month_year_user: "submission_status = 'submitted'"
  end

  code_interface do
    define :read, action: :read
    define :get, get_by: [:id]
    define :by_month, args: [:user_id, :month, :year]
    define :create
    define :request_change
    define :accept_change_request
    define :reject_change_request
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

      filter expr(
               user_id == ^arg(:user_id) and month == ^arg(:month) and year == ^arg(:year) and
                 submission_status == :submitted
             )
    end

    read :list do
      description "List monthly hour records with optional user and period filters."
      argument :user_id, :uuid
      argument :month, :integer
      argument :year, :integer

      argument :submission_status, :atom do
        default :submitted
        constraints one_of: [:submitted, :withdrawn]
      end

      prepare build(sort: [inserted_at: :desc, id: :desc])

      prepare build(filter: expr(submission_status == ^arg(:submission_status))) do
        where present(:submission_status)
      end

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

    update :request_change do
      primary? true
      description "Request correction or cancellation without unlocking the submitted record."
      accept [:change_request_kind, :change_request_reason]
      require_atomic? false

      validate present([:change_request_kind, :change_request_reason])
      validate attribute_equals(:submission_status, :submitted)
      change filter(expr(is_nil(change_requested_at) and submission_status == :submitted))
      change set_attribute(:change_requested_at, &DateTime.utc_now/0)
      validate changing(:change_requested_at, from: nil)

      change after_action(fn _changeset, record, _context ->
               with {:ok, _job} <-
                      Firmowid.Ash.Timetracker.Workers.HoursRecordChangeEmailWorker.enqueue(
                        record.id,
                        record.organization_id
                      ) do
                 {:ok, record}
               end
             end)
    end

    update :accept_change_request do
      description "Approve the request, retaining the document and unlocking its month for a new submission."
      accept []
      validate PendingHoursRecordChange

      change filter(
               expr(
                 submission_status == :submitted and not is_nil(change_requested_at) and
                   is_nil(change_request_decision) and organization_id == ^actor(:organization_id)
               )
             )

      change set_attribute(:change_request_decision, :accepted)
      change set_attribute(:change_reviewed_at, &DateTime.utc_now/0)
      change set_attribute(:change_reviewer_id, actor(:id))
      change set_attribute(:submission_status, :withdrawn)
    end

    update :reject_change_request do
      description "Reject the request without changing the submitted document or unlocking its month."
      accept []
      validate PendingHoursRecordChange

      change filter(
               expr(
                 submission_status == :submitted and not is_nil(change_requested_at) and
                   is_nil(change_request_decision) and organization_id == ^actor(:organization_id)
               )
             )

      change set_attribute(:change_request_decision, :rejected)
      change set_attribute(:change_reviewed_at, &DateTime.utc_now/0)
      change set_attribute(:change_reviewer_id, actor(:id))
    end

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
    bypass {Firmowid.Ash.Checks.SystemActorRole, roles: [:hours_record_change_notifier]} do
      authorize_if action_type(:read)
    end

    policy Firmowid.Ash.Checks.IsSystemActor do
      forbid_if always()
    end

    policy action_type(:read) do
      authorize_if relates_to_actor_via(:user)
    end

    policy action_type(:create) do
      authorize_if relating_to_actor(:user)
    end

    policy action(:request_change) do
      authorize_if relates_to_actor_via(:user)
    end

    policy action([:accept_change_request, :reject_change_request]) do
      authorize_if actor_attribute_equals(:role, :admin)
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

    attribute :submission_status, :atom do
      public? true
      allow_nil? false
      default :submitted
      constraints one_of: [:submitted, :withdrawn]
    end

    attribute :change_request_kind, :atom do
      public? true
      constraints one_of: [:correction, :cancellation]
    end

    attribute :change_request_reason, :string do
      public? true
      constraints min_length: 1, max_length: 2000, trim?: true, allow_empty?: false
    end

    attribute :change_requested_at, :utc_datetime_usec

    attribute :change_request_decision, :atom do
      public? true
      constraints one_of: [:accepted, :rejected]
    end

    attribute :change_reviewed_at, :utc_datetime_usec
  end

  relationships do
    belongs_to :user, User do
      allow_nil? false
      attribute_writable? true
    end

    belongs_to :blob, Firmowid.Ash.Blobs.Blob do
      allow_nil? false
      attribute_writable? true
    end

    belongs_to :change_reviewer, User do
      allow_nil? true
    end

    belongs_to :organization, Firmowid.Ash.Core.Organization do
      allow_nil? false
    end
  end

  identities do
    identity :unique_month_year_user, [:month, :year, :user_id, :organization_id] do
      where expr(submission_status == :submitted)
    end
  end
end
