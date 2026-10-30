# credo:disable-for-this-file AshCredo.Check.Design.MissingPrimaryAction
defmodule Firmowid.Timetracker.LeaveRequest do
  @moduledoc "Represents a leave or absence request submitted by an employee.
  The request can be accepted or declined by an admin."

  use Ash.Resource,
    otp_app: :firmowid,
    domain: Firmowid.Timetracker,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshStateMachine]

  use Gettext, backend: Firmowid.Gettext

  alias Firmowid.Blobs
  alias Firmowid.Checks.ActorRole
  alias Firmowid.Checks.SystemActorRole
  alias Firmowid.Core.Member
  alias Firmowid.Resource
  alias Firmowid.Timetracker.Actions.NotifyAdminsAboutLeaveRequest
  alias Firmowid.Timetracker.Signals

  require Resource

  postgres do
    table "leave_requests"
    repo Firmowid.Repo

    references do
      reference :member, on_delete: :delete
    end

    exclusion_constraint_names [
      {:starts_on, "no_overlapping_leave_requests", "nachodzi na inny wniosek urlopowy"}
    ]

    custom_statements do
      statement :no_overlapping_leave_requests do
        up """
        ALTER TABLE leave_requests
        ADD CONSTRAINT no_overlapping_leave_requests
        EXCLUDE USING gist (
          member_id WITH =,
          daterange(starts_on, ends_on, '[]') WITH &&
        )
        WHERE (status IN ('accepted', 'pending'));
        """

        down """
        ALTER TABLE leave_requests
        DROP CONSTRAINT no_overlapping_leave_requests;
        """
      end
    end
  end

  state_machine do
    state_attribute :status
    initial_states [:pending]
    default_initial_state :pending

    transitions do
      transition :accept, from: :pending, to: :accepted
      transition :decline, from: :pending, to: :declined
    end
  end

  code_interface do
    define :read, action: :read
    define :list, action: :list
    define :destroy, action: :destroy
    define :notify_admins, args: [:signal]
  end

  actions do
    defaults [:read]

    destroy :destroy do
      description "Delete a leave request."
      primary? true
    end

    read :list do
      description "List leave requests with optional member, overlapping date range and status filters."
      argument :member_id, :uuid
      argument :start_date, :date
      argument :end_date, :date

      argument :status, :atom do
        constraints one_of: [:pending, :accepted, :declined]
      end

      prepare build(filter: expr(member_id == ^arg(:member_id))) do
        where present(:member_id)
      end

      prepare build(filter: expr(ends_on >= ^arg(:start_date))) do
        where present(:start_date)
      end

      prepare build(filter: expr(starts_on <= ^arg(:end_date))) do
        where present(:end_date)
      end

      prepare build(filter: expr(status == ^arg(:status))) do
        where present(:status)
      end
    end

    read :list_for_member do
      description "Leave requests of a given organization member."
      argument :member_id, :uuid, allow_nil?: false
      argument :start_date, :date, allow_nil?: true
      argument :end_date, :date, allow_nil?: true

      prepare build(filter: expr(member_id == ^arg(:member_id)), sort: [inserted_at: :desc])

      prepare build(filter: expr(ends_on >= ^arg(:start_date))) do
        where present(:start_date)
      end

      prepare build(filter: expr(starts_on <= ^arg(:end_date))) do
        where present(:end_date)
      end
    end

    read :list_current_user do
      description "Leave requests submitted by the acting user."

      argument :start_date, :date, allow_nil?: true
      argument :end_date, :date, allow_nil?: true

      pagination offset?: true,
                 countable: true,
                 default_limit: 25,
                 max_page_size: 100,
                 required?: false

      prepare build(filter: expr(member_id == ^actor([:member, :id])), sort: [inserted_at: :desc])

      prepare build(filter: expr(ends_on >= ^arg(:start_date))) do
        where present(:start_date)
      end

      prepare build(filter: expr(starts_on <= ^arg(:end_date))) do
        where present(:end_date)
      end
    end

    create :create do
      description "Employee submits a leave/absence request."
      primary? true
      accept [:starts_on, :ends_on, :note]

      argument :reason, :atom do
        allow_nil? false
        constraints one_of: [:indisposition, :rest, :other]

        description "Request reason: indisposition, rest, or other. This action only creates absence requests."
      end

      change set_attribute(:member_id, actor([:member, :id]))
      change set_attribute(:reason, arg(:reason))

      # TODO: Determine category based on employment contract

      validate one_of(:reason, [:sick, :vacation, :unpaid]) do
        where [attribute_equals(:category, :leave)]
        message gettext_noop("is not valid for this leave category")
      end

      validate one_of(:reason, [:indisposition, :rest, :other]) do
        where [attribute_equals(:category, :absence)]
        message gettext_noop("is not valid for this absence category")
      end

      validate compare(:starts_on, greater_than_or_equal_to: &Date.utc_today/0) do
        message gettext_noop("must be today or later")
      end

      validate compare(:ends_on, greater_than_or_equal_to: :starts_on) do
        message gettext_noop("cannot be earlier than the start date")
      end

      emit Signals, :leave_request_submitted, fields: [leave_request_id: :id]
    end

    create :create_with_upload do
      description "Employee submits a leave or absence request with a browser-uploaded attachment."
      accept [:starts_on, :ends_on, :note]

      argument :reason, :atom do
        allow_nil? false
        constraints one_of: [:indisposition, :rest, :other]
      end

      argument :upload_path, :string do
        allow_nil? false
        description "Path from the server-managed browser upload temporary directory."
      end

      argument :upload_filename, :string do
        allow_nil? false
        description "Original filename of the uploaded attachment."
      end

      change set_attribute(:member_id, actor([:member, :id]))
      change set_attribute(:reason, arg(:reason))

      change fn changeset, context ->
        upload_path = Ash.Changeset.get_argument(changeset, :upload_path)
        upload_filename = Ash.Changeset.get_argument(changeset, :upload_filename)

        case Blobs.create_or_reuse_blob(
               upload_path,
               "binary/octet-stream",
               upload_filename,
               tenant: context.tenant,
               actor: context.actor
             ) do
          {:ok, blob} ->
            Ash.Changeset.force_change_attribute(changeset, :blob_id, blob.id)

          {:error, error} ->
            Ash.Changeset.add_error(changeset, error)
        end
      end

      validate one_of(:reason, [:sick, :vacation, :unpaid]) do
        where [attribute_equals(:category, :leave)]
        message gettext_noop("is not valid for this leave category")
      end

      validate one_of(:reason, [:indisposition, :rest, :other]) do
        where [attribute_equals(:category, :absence)]
        message gettext_noop("is not valid for this absence category")
      end

      validate compare(:starts_on, greater_than_or_equal_to: &Date.utc_today/0) do
        message gettext_noop("must be today or later")
      end

      validate compare(:ends_on, greater_than_or_equal_to: :starts_on) do
        message gettext_noop("cannot be earlier than the start date")
      end

      emit Signals, :leave_request_submitted, fields: [leave_request_id: :id]
    end

    update :accept do
      description "Admin accepts a pending leave request."
      require_atomic? false
      accept []
      change transition_state(:accepted)
    end

    update :decline do
      description "Admin declines a pending leave request."
      require_atomic? false
      accept []

      validate attribute_equals(:category, :leave),
        message: gettext_noop("only leave requests can be declined")

      change transition_state(:declined)
    end

    action :notify_admins do
      description "Emails organization admins about a newly submitted leave request."
      argument :signal, Signals.LeaveRequestSubmitted, allow_nil?: false
      run NotifyAdminsAboutLeaveRequest
    end
  end

  policies do
    bypass [
      {SystemActorRole, roles: [:organization_cleanup]},
      action([:read, :list, :destroy])
    ] do
      authorize_if expr(not is_nil(^actor(:org_id)) and organization_id == ^actor(:org_id))
    end

    bypass {ActorRole, role: :admin} do
      authorize_if always()
    end

    bypass [{SystemActorRole, roles: [:leave_notifier, :avatar_cleanup]}, action_type(:read)] do
      authorize_if expr(^actor(:role) == :leave_notifier or blob_id == ^actor(:blob_id))
    end

    policy action(:create) do
      authorize_if actor_present()
    end

    policy action(:notify_admins) do
      authorize_if signal_in(Signals, :leave_request_submitted)
    end

    policy action_type(:read) do
      authorize_if expr(member_id == ^actor([:member, :id]))
    end

    policy action([:accept, :decline]) do
      forbid_if always()
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :starts_on, :date, allow_nil?: false, public?: true
    attribute :ends_on, :date, allow_nil?: false, public?: true
    attribute :note, :string, public?: true, allow_nil?: true

    attribute :category, :atom do
      allow_nil? false
      public? true
      default :absence
      constraints one_of: [:leave, :absence]
    end

    attribute :reason, :atom do
      allow_nil? false
      public? true

      constraints one_of: [
                    :sick,
                    :vacation,
                    :unpaid,
                    :indisposition,
                    :rest,
                    :other
                  ]
    end

    attribute :status, :atom do
      allow_nil? false
      public? true
      default :pending
      constraints one_of: [:pending, :accepted, :declined]
    end

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :member, Member do
      allow_nil? false
      attribute_writable? true
    end

    belongs_to :organization, Firmowid.Core.Organization do
      allow_nil? false
    end

    belongs_to :blob, Firmowid.Blobs.Blob do
      allow_nil? true
      attribute_writable? true
    end
  end

  signals_in do
    from Signals do
      on :leave_request_submitted, :notify_admins,
        delivery: {AshOban.Signals, queue: :notification_emails, max_attempts: 3}
    end
  end

  calculations do
    calculate :days_count,
              :integer,
              expr(
                fragment(
                  "(SELECT count(*)::integer FROM generate_series(?::date, ?::date, '1 day'::interval) AS gs(date) WHERE EXTRACT(isodow FROM gs.date) < 6)",
                  starts_on,
                  ends_on
                )
              ) do
      public? true
    end

    calculate :clamped_days_in_year,
              :integer,
              expr(
                if starts_on > ^arg(:year_end) or ends_on < ^arg(:year_start) do
                  0
                else
                  fragment(
                    "(SELECT count(*)::integer FROM generate_series(?::date, ?::date, '1 day'::interval) AS gs(date) WHERE EXTRACT(isodow FROM gs.date) < 6)",
                    if(starts_on < ^arg(:year_start), do: ^arg(:year_start), else: starts_on),
                    if(ends_on > ^arg(:year_end), do: ^arg(:year_end), else: ends_on)
                  )
                end
              ) do
      argument :year_start, :date, allow_nil?: false
      argument :year_end, :date, allow_nil?: false
    end
  end
end
