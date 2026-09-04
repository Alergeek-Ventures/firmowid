# credo:disable-for-this-file AshCredo.Check.Design.MissingPrimaryAction
defmodule Firmowid.Ash.Timetracker.LeaveRequest do
  @moduledoc "Represents a leave or absence request submitted by an employee.
  The request can be accepted or declined by an admin."

  use Ash.Resource,
    otp_app: :firmowid,
    domain: Firmowid.Ash.Timetracker,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshStateMachine],
    primary_read_warning?: false

  alias Firmowid.Ash.Blobs
  alias Firmowid.Ash.Core.User
  alias Firmowid.Ash.Resource
  alias Firmowid.Ash.Timetracker.Workers.LeaveRequestEmailWorker

  require Resource

  postgres do
    table "leave_requests"
    repo Firmowid.Repo

    exclusion_constraint_names [
      {:starts_on, "no_overlapping_leave_requests", "nachodzi na inny wniosek urlopowy"}
    ]

    custom_statements do
      statement :no_overlapping_leave_requests do
        up """
        ALTER TABLE leave_requests
        ADD CONSTRAINT no_overlapping_leave_requests
        EXCLUDE USING gist (
          user_id WITH =,
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

  actions do
    defaults [:read]

    read :list_for_user do
      description "Leave requests for a given user."
      argument :user_id, :uuid, allow_nil?: false
      argument :start_date, :date, allow_nil?: true
      argument :end_date, :date, allow_nil?: true

      prepare build(filter: expr(user_id == ^arg(:user_id)), sort: [inserted_at: :desc])

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

      prepare build(filter: expr(user_id == ^actor(:id)), sort: [inserted_at: :desc])

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

      change set_attribute(:user_id, actor(:id))
      change set_attribute(:reason, arg(:reason))

      # TODO: Determine category based on employment contract

      validate one_of(:reason, [:sick, :vacation, :unpaid]) do
        where [attribute_equals(:category, :leave)]
        message "nie jest prawidłowy dla tej kategorii urlopu"
      end

      validate one_of(:reason, [:indisposition, :rest, :other]) do
        where [attribute_equals(:category, :absence)]
        message "nie jest prawidłowy dla tej kategorii nieobecności"
      end

      validate compare(:starts_on, greater_than_or_equal_to: &Date.utc_today/0) do
        message "musi być dzisiejsza lub późniejsza"
      end

      validate compare(:ends_on, greater_than_or_equal_to: :starts_on) do
        message "musi być na lub po dacie rozpoczęcia"
      end

      change after_transaction(fn
               _changeset, {:ok, leave_request}, _context ->
                 LeaveRequestEmailWorker.enqueue(leave_request.id, leave_request.organization_id)
                 {:ok, leave_request}

               _changeset, {:error, reason}, _context ->
                 {:error, reason}
             end)
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

      change set_attribute(:user_id, actor(:id))
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
        message "nie jest prawidłowy dla tej kategorii urlopu"
      end

      validate one_of(:reason, [:indisposition, :rest, :other]) do
        where [attribute_equals(:category, :absence)]
        message "nie jest prawidłowy dla tej kategorii nieobecności"
      end

      validate compare(:starts_on, greater_than_or_equal_to: &Date.utc_today/0) do
        message "musi być dzisiejsza lub późniejsza"
      end

      validate compare(:ends_on, greater_than_or_equal_to: :starts_on) do
        message "musi być na lub po dacie rozpoczęcia"
      end

      change after_transaction(fn
               _changeset, {:ok, leave_request}, _context ->
                 LeaveRequestEmailWorker.enqueue(leave_request.id, leave_request.organization_id)
                 {:ok, leave_request}

               _changeset, {:error, reason}, _context ->
                 {:error, reason}
             end)
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
        message: "można odrzucać tylko wnioski urlopowe"

      change transition_state(:declined)
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :admin) do
      authorize_if always()
    end

    bypass {Firmowid.Ash.Checks.SystemActorRole, roles: [:leave_notifier]} do
      authorize_if action_type(:read)
    end

    policy action(:create) do
      authorize_if actor_present()
    end

    policy action_type(:read) do
      authorize_if expr(user_id == ^actor(:id))
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
    belongs_to :user, User do
      allow_nil? false
      attribute_writable? true
    end

    belongs_to :organization, Firmowid.Ash.Core.Organization do
      allow_nil? false
    end

    belongs_to :blob, Firmowid.Ash.Blobs.Blob do
      allow_nil? true
      attribute_writable? true
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
