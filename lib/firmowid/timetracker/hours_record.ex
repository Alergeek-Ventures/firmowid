defmodule Firmowid.Timetracker.HoursRecord do
  @moduledoc """
  Ash resource wrapping the existing `hours_records` table.

  Attribute multitenancy via `organization_id`. Stores the number of hours
  worked by a member in a given month/year, with an attached blob (uploaded
  hours record document).
  """
  use Ash.Resource,
    domain: Firmowid.Timetracker,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Blobs
  alias Firmowid.Checks.ActorRole
  alias Firmowid.Checks.CreatingForActorMember
  alias Firmowid.Checks.SystemActorRole
  alias Firmowid.Core.User
  alias Firmowid.Resource
  alias Firmowid.Timetracker.Actions.NotifyAdminsAboutHoursRecordChange
  alias Firmowid.Timetracker.Signals
  alias Firmowid.Timetracker.Validations.PendingHoursRecordChange

  require Resource

  postgres do
    table "hours_records"
    repo Firmowid.Repo
    identity_wheres_to_sql unique_month_year_member: "submission_status = 'submitted'"

    references do
      reference :member, on_delete: :delete
    end

    custom_indexes do
      index [:member_id]
    end
  end

  code_interface do
    define :read, action: :read
    define :get, get_by: [:id]
    define :by_month, args: [:member_id, :month, :year]
    define :create
    define :request_change
    define :accept_change_request
    define :reject_change_request
    define :notify_admins, args: [:signal]
  end

  actions do
    defaults [:read]

    # ── Read actions ──────────────────────────────────────────────────

    read :get do
      description "Get a single hours record by ID with its member's user preloaded."
      get? true

      prepare build(load: [member: :user])
    end

    read :by_month do
      description "Get the submitted hours record of a member in a specific month/year."
      get? true

      argument :member_id, :uuid, allow_nil?: false
      argument :month, :integer, allow_nil?: false
      argument :year, :integer, allow_nil?: false

      filter expr(
               member_id == ^arg(:member_id) and month == ^arg(:month) and year == ^arg(:year) and
                 submission_status == :submitted
             )
    end

    read :list do
      description "List monthly hour records with optional member and period filters."
      argument :member_id, :uuid
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

      prepare build(filter: expr(member_id == ^arg(:member_id))) do
        where present(:member_id)
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

      emit Signals, :hours_record_change_requested, fields: [hours_record_id: :id]
    end

    update :accept_change_request do
      description "Approve the request, retaining the document and unlocking its month for a new submission."
      accept []
      validate PendingHoursRecordChange

      change filter(
               expr(
                 submission_status == :submitted and not is_nil(change_requested_at) and
                   is_nil(change_request_decision) and
                   organization_id == ^actor([:member, :organization_id])
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
                   is_nil(change_request_decision) and
                   organization_id == ^actor([:member, :organization_id])
               )
             )

      change set_attribute(:change_request_decision, :rejected)
      change set_attribute(:change_reviewed_at, &DateTime.utc_now/0)
      change set_attribute(:change_reviewer_id, actor(:id))
    end

    create :create do
      description "Create an hours record with blob upload. The blob is created from the uploaded file."
      accept [:month, :year, :number_of_hours, :member_id]

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

    action :notify_admins do
      description "Emails organization admins about an hours record change request."
      argument :signal, Signals.HoursRecordChangeRequested, allow_nil?: false
      run NotifyAdminsAboutHoursRecordChange
    end
  end

  policies do
    bypass [{SystemActorRole, roles: [:avatar_cleanup]}, action(:read)] do
      authorize_if expr(blob_id == ^actor(:blob_id))
    end

    bypass {SystemActorRole, roles: [:hours_record_change_notifier]} do
      authorize_if action_type(:read)
    end

    policy Firmowid.Checks.IsSystemActor do
      forbid_if always()
    end

    policy action_type(:read) do
      authorize_if expr(member_id == ^actor([:member, :id]))
    end

    policy action_type(:create) do
      authorize_if CreatingForActorMember
    end

    policy action(:request_change) do
      authorize_if expr(member_id == ^actor([:member, :id]))
    end

    policy action([:accept_change_request, :reject_change_request]) do
      authorize_if {ActorRole, role: :admin}
    end

    policy action(:notify_admins) do
      authorize_if signal_in(Signals, :hours_record_change_requested)
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
    belongs_to :member, Firmowid.Core.Member do
      allow_nil? false
      attribute_writable? true
    end

    belongs_to :blob, Firmowid.Blobs.Blob do
      allow_nil? false
      attribute_writable? true
    end

    belongs_to :change_reviewer, User do
      allow_nil? true
    end

    belongs_to :organization, Firmowid.Core.Organization do
      allow_nil? false
    end
  end

  signals_in do
    from Signals do
      on :hours_record_change_requested, :notify_admins, delivery: {AshOban.Signals, queue: :default, max_attempts: 3}
    end
  end

  identities do
    identity :unique_month_year_member, [:month, :year, :member_id, :organization_id] do
      where expr(submission_status == :submitted)
    end
  end
end
