# credo:disable-for-this-file AshCredo.Check.Design.MissingPrimaryAction
# credo:disable-for-this-file AshCredo.Check.Warning.AuthorizeFalse
defmodule Firmowid.Delegations.Delegation do
  @moduledoc "A company-funded business trip submitted by an employee."

  use Ash.Resource,
    otp_app: :firmowid,
    domain: Firmowid.Delegations,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshStateMachine],
    fragments: [
      Firmowid.Delegations.Delegation.Policies,
      Firmowid.Delegations.Delegation.PerDiemAttributes
    ]

  use Gettext, backend: Firmowid.Gettext

  alias Firmowid.Blobs.Blob
  alias Firmowid.Core.Member
  alias Firmowid.Delegations.Actions.NotifyAdminsAboutDelegation
  alias Firmowid.Delegations.Actions.NotifyAdminsAboutSubmittedSettlement
  alias Firmowid.Delegations.Actions.NotifyEmployeeAboutApprovedDelegation
  alias Firmowid.Delegations.Actions.NotifyEmployeeAboutReviewedSettlement
  alias Firmowid.Delegations.Changes.AssignReference
  alias Firmowid.Delegations.Changes.CreateSignedCommandBlob
  alias Firmowid.Delegations.Changes.CreateSignedSettlementBlob
  alias Firmowid.Delegations.Changes.PrepareDelegationCompletion
  alias Firmowid.Delegations.Changes.PrepareSettlement
  alias Firmowid.Delegations.Changes.SetPerDiemExchangeRate
  alias Firmowid.Delegations.Changes.SetSubmittedAt
  alias Firmowid.Delegations.Signals
  alias Firmowid.Delegations.Validations.HasDateChangeReason
  alias Firmowid.Delegations.Validations.HasExpenses
  alias Firmowid.Delegations.Validations.PerDiemTimesComplete
  alias Firmowid.Resource

  require Resource

  @per_diem_fields [
    :trip_started_at,
    :trip_ended_at,
    :abroad_started_at,
    :abroad_ended_at,
    :provided_breakfasts,
    :provided_lunches,
    :provided_dinners,
    :lump_sum_nights,
    :local_transport_lump_sum,
    :station_transfers
  ]

  postgres do
    table "delegations"
    repo Firmowid.Repo

    references do
      reference :member, on_delete: :delete
    end
  end

  state_machine do
    state_attribute :status
    initial_states [:pending]
    default_initial_state :pending

    transitions do
      transition :approve, from: :pending, to: :in_progress
      transition :prepare_settlement, from: :in_progress, to: :awaiting_signature
      transition :edit_settlement, from: :awaiting_signature, to: :in_progress
      transition :submit_for_review, from: :awaiting_signature, to: :submitted
      transition :accept_settlement, from: :submitted, to: :complete
      transition :return_settlement, from: :submitted, to: :in_progress
    end
  end

  actions do
    defaults [:read]

    read :by_reference do
      description "Find a delegation by its public reference."
      get? true

      argument :reference, :string, allow_nil?: false
      filter expr(reference == ^arg(:reference))
    end

    read :list_for_member do
      description "Delegations submitted by a given organization member."
      argument :member_id, :uuid, allow_nil?: false
      prepare build(filter: expr(member_id == ^arg(:member_id)), sort: [inserted_at: :desc])
    end

    create :create do
      description "Submit a new business trip delegation."
      primary? true

      accept [
        :title,
        :billing_month,
        :destination,
        :destination_country,
        :transport_types,
        :purpose,
        :expected_cost,
        :start_date,
        :end_date
      ]

      change set_attribute(:member_id, actor([:member, :id]))
      change set_attribute(:reference, "pending")
      change AssignReference

      validate compare(:end_date, greater_than_or_equal_to: :start_date),
        message: gettext_noop("cannot be earlier than the departure date")

      validate compare(:expected_cost, greater_than_or_equal_to: Money.new(:PLN, 0)),
        message: gettext_noop("must be greater than or equal to 0 PLN")

      emit Signals, :delegation_submitted, fields: [delegation_id: :id]
    end

    update :approve do
      description "Approve a pending delegation and mark it as in progress."
      primary? true
      require_atomic? false
      accept [:advance_amount, :signed_command_filename]

      argument :upload_path, :string, allow_nil?: false

      argument :content_type, :string,
        allow_nil?: false,
        constraints: [match: ~r/^application\/pdf$/]

      change CreateSignedCommandBlob
      validate present(:signed_command_filename)

      validate compare(:advance_amount, greater_than_or_equal_to: Money.new(:PLN, 0)),
        message: gettext_noop("must be greater than or equal to 0 PLN")

      change SetPerDiemExchangeRate
      change transition_state(:in_progress)

      emit Signals, :delegation_approved, fields: [delegation_id: :id]
    end

    update :prepare_command do
      description "Set the advance amount used in a pending business trip order."
      require_atomic? false
      accept [:advance_amount]
      validate attribute_equals(:status, :pending)

      validate compare(:advance_amount, greater_than_or_equal_to: Money.new(:PLN, 0)),
        message: gettext_noop("must be greater than or equal to 0 PLN")
    end

    update :update_billing_month do
      description "Set the billing month for a pending business trip delegation."
      require_atomic? false
      accept [:billing_month]
      validate attribute_equals(:status, :pending)
    end

    update :save_draft do
      description "Save editable settlement fields without completing the delegation."
      require_atomic? false
      accept [:date_change_reason | @per_diem_fields]
      argument :expenses, {:array, :map}, allow_nil?: false, default: []

      validate attribute_equals(:status, :in_progress)

      change manage_relationship(:expenses,
               type: :direct_control,
               on_match: {:update, :update},
               on_no_match: :error,
               on_missing: :ignore,
               # The parent authorizes the owner and limits updates to this delegation's expenses.
               authorize?: false
             )
    end

    update :prepare_settlement do
      description "Validate an in-progress settlement and prepare it for employee signature."
      require_atomic? false
      accept [:date_change_reason | @per_diem_fields]

      argument :expenses, {:array, :map}, allow_nil?: false, default: []

      change PrepareDelegationCompletion

      change manage_relationship(:expenses,
               type: :direct_control,
               on_match: {:update, :complete},
               on_no_match: :error,
               on_missing: :ignore,
               # The parent completion action authorizes the employee and owns this transaction.
               authorize?: false
             )

      # Runs after Ash requires values, so the per diem it checks is calculated from cast inputs.
      validate {HasExpenses, []}, before_action?: true
      validate {HasDateChangeReason, []}
      validate {PerDiemTimesComplete, []}

      change PrepareSettlement
      change transition_state(:awaiting_signature)
    end

    update :edit_settlement do
      description "Reopen a prepared settlement for corrections."
      change transition_state(:in_progress)
    end

    update :submit_for_review do
      description "Store the signed settlement and submit it to the employer for review."
      require_atomic? false
      accept []

      argument :upload_path, :string, allow_nil?: false

      argument :content_type, :string,
        allow_nil?: false,
        constraints: [match: ~r/^application\/pdf$/]

      argument :original_filename, :string, allow_nil?: false

      change CreateSignedSettlementBlob
      change SetSubmittedAt
      change set_attribute(:settlement_return_reason, nil)
      change transition_state(:submitted)

      emit Signals, :settlement_submitted, fields: [delegation_id: :id]
    end

    update :accept_settlement do
      description "Accept a submitted settlement and close the delegation."
      accept []
      change transition_state(:complete)

      emit Signals, :settlement_reviewed, fields: [delegation_id: :id, reason: :settlement_return_reason]
    end

    update :return_settlement do
      description "Return a submitted settlement to the employee for corrections."
      accept [:settlement_return_reason]
      validate present(:settlement_return_reason)
      change transition_state(:in_progress)

      emit Signals, :settlement_reviewed, fields: [delegation_id: :id, reason: :settlement_return_reason]
    end

    update :detect_dates do
      description "Store delegation dates detected from its evidence documents."
      require_atomic? false
      accept [:detected_start_date, :detected_end_date]
    end

    action :notify_admins do
      description "Emails organization admins about a newly submitted delegation."
      argument :signal, Signals.DelegationSubmitted, allow_nil?: false
      run NotifyAdminsAboutDelegation
    end

    action :notify_employee do
      description "Emails the employee that their delegation was approved."
      argument :signal, Signals.DelegationApproved, allow_nil?: false
      run NotifyEmployeeAboutApprovedDelegation
    end

    action :notify_admins_about_settlement do
      description "Emails organization admins that a signed settlement awaits review."
      argument :signal, Signals.SettlementSubmitted, allow_nil?: false
      run NotifyAdminsAboutSubmittedSettlement
    end

    action :notify_employee_about_settlement do
      description "Emails the employee that their settlement was accepted or returned."
      argument :signal, Signals.SettlementReviewed, allow_nil?: false
      run NotifyEmployeeAboutReviewedSettlement
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :reference, :string, allow_nil?: false, public?: true
    attribute :title, :string, allow_nil?: false, public?: true
    attribute :billing_month, :date, allow_nil?: false, public?: true
    attribute :destination, :string, allow_nil?: false, public?: true

    attribute :destination_country, :string,
      allow_nil?: false,
      default: "PL",
      public?: true,
      description: "ISO 3166-1 alpha-2 code of the destination, as used by the country select."

    attribute :transport_types, {:array, :atom},
      allow_nil?: false,
      public?: true,
      constraints: [
        min_length: 1,
        items: [one_of: [:railway, :airplane, :bus, :public_transport, :other]]
      ]

    attribute :purpose, :string, allow_nil?: false, public?: true
    attribute :expected_cost, AshMoney.Types.Money, allow_nil?: false, public?: true

    attribute :advance_amount, AshMoney.Types.Money,
      allow_nil?: false,
      default: Money.new(:PLN, 0),
      public?: true

    attribute :signed_command_filename, :string, public?: true
    attribute :start_date, :date, allow_nil?: false, public?: true
    attribute :end_date, :date, allow_nil?: false, public?: true
    attribute :detected_start_date, :date, public?: true
    attribute :detected_end_date, :date, public?: true
    attribute :date_change_reason, :string, public?: true

    attribute :status, :atom do
      allow_nil? false
      default :pending
      public? true
      constraints one_of: [:pending, :in_progress, :awaiting_signature, :submitted, :complete]
    end

    attribute :settlement_sequence, :integer, public?: true, constraints: [min: 1]
    attribute :settlement_year, :integer, public?: true, constraints: [min: 2000]
    attribute :settlement_prepared_at, :utc_datetime, public?: true
    attribute :submitted_at, :utc_datetime, public?: true
    attribute :settlement_return_reason, :string, public?: true

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

    belongs_to :signed_command_blob, Blob do
      description "Employer-signed business trip order."
      allow_nil? true
      attribute_writable? true
    end

    belongs_to :signed_settlement_blob, Blob do
      description "Employee-signed delegation settlement submitted for employer review."
      allow_nil? true
      attribute_writable? true
    end

    has_many :expenses, Firmowid.Delegations.DelegationExpense
  end

  signals_in do
    from Signals do
      on :delegation_submitted, :notify_admins, delivery: {AshOban.Signals, queue: :notification_emails, max_attempts: 3}

      on :delegation_approved, :notify_employee, delivery: {AshOban.Signals, queue: :notification_emails, max_attempts: 3}

      on :settlement_submitted, :notify_admins_about_settlement,
        delivery: {AshOban.Signals, queue: :notification_emails, max_attempts: 3}

      on :settlement_reviewed, :notify_employee_about_settlement,
        delivery: {AshOban.Signals, queue: :notification_emails, max_attempts: 3}
    end
  end

  aggregates do
    sum :expenses_total, :expenses, :expense_amount
  end

  identities do
    identity :unique_reference, [:organization_id, :reference]

    identity :unique_settlement_number, [
      :organization_id,
      :settlement_year,
      :settlement_sequence
    ]
  end
end
