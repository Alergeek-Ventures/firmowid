# Every update is a payment step with side effects, so none is a safe primary.
# credo:disable-for-this-file AshCredo.Check.Design.MissingPrimaryAction
# The primary read serves relationships; `:read_global` and `:issue_invoice` run only from AshOban triggers.
# credo:disable-for-this-file AshCredo.Check.Design.MissingCodeInterface
defmodule Firmowid.Billing.Payment do
  @moduledoc """
  What a subscription charges its saved card for: one paid-for period, its amount and the
  attempts to collect it at Tpay. Its id names the attempt at Tpay and becomes the id of its
  advance invoice.

  `:charge` claims the next attempt in the database, commits it and only then asks Tpay, so a
  repeated job or a crash never charges the card twice: a payment left `:charging` is settled by
  `:record_outcome`, which the charge, the hourly reconciliation and Tpay's notification share and
  which owns every effect of an outcome. A declined attempt is tried again on the 4th and 8th day
  of the period while `max_attempts` allows; after the last one the payment fails and its
  subscription ends.

  An `:upgrade` payment (the price difference of a move to a more expensive plan) has a single
  attempt, charged only while the admin who asked for it waits (never by the daily charge):
  paid, it moves the subscription to its plan; failed, it changes nothing else.

  A declined attempt's transaction is cancelled at Tpay, so nobody can pay it later.
  """

  use Ash.Resource,
    domain: Firmowid.Billing,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshStateMachine, AshOban],
    notifiers: [Ash.Notifier.PubSub]

  alias AshOban.Checks.AshObanInteraction
  alias Firmowid.Billing.Payment.Changes.ApplyOutcome
  alias Firmowid.Billing.Payment.Changes.ChargeCard
  alias Firmowid.Billing.Payment.Changes.EndSubscriptionOnFailure
  alias Firmowid.Billing.Payment.Changes.FetchOutcome
  alias Firmowid.Billing.Payment.Changes.FollowUpDecline
  alias Firmowid.Billing.Payment.Changes.IssueAdvanceInvoice
  alias Firmowid.Billing.Payment.Changes.PricePeriod
  alias Firmowid.Billing.Payment.Changes.ReleaseClaim
  alias Firmowid.Billing.Payment.Changes.SwitchUpgradedPlan
  alias Firmowid.Billing.Subscription
  alias Firmowid.Checks.ActorRole
  alias Firmowid.Checks.IsSystemActor
  alias Firmowid.Checks.SystemActorRole
  alias Firmowid.Resource

  require Resource

  @statuses [:due, :charging, :paid, :declined, :failed]

  postgres do
    table "billing_payments"
    repo Firmowid.Repo

    identity_wheres_to_sql one_per_period: "status != 'failed'"
  end

  state_machine do
    state_attribute :status
    initial_states [:due]
    default_initial_state :due

    transitions do
      transition :charge, from: [:due, :declined], to: :charging
      transition :release, from: :charging, to: [:due, :declined]
      transition :record_outcome, from: [:charging, :declined], to: [:paid, :declined, :failed]
    end
  end

  oban do
    use_tenant_from_record? true

    triggers do
      trigger :charge do
        action :charge
        read_action :read_global
        # An upgrade is charged only while its admin waits for it (`Subscription :upgrade`).
        where expr(due? and kind == :period)
        scheduler_cron "0 8 * * *"
        # A failed charge is never retried by the job: it may have reached Tpay.
        max_attempts 1
        queue :billing_charges

        worker_module_name Firmowid.Billing.Payment.Worker.Charge
        scheduler_module_name Firmowid.Billing.Payment.Scheduler.Charge
      end

      # Settles a charge whose outcome is still unknown an hour after its claim.
      trigger :reconcile do
        action :record_outcome
        read_action :read_global
        where expr(status == :charging and updated_at < ago(1, "hour"))
        scheduler_cron "0 8-20 * * *"
        max_attempts 1
        queue :billing_charges

        worker_module_name Firmowid.Billing.Payment.Worker.Reconcile
        scheduler_module_name Firmowid.Billing.Payment.Scheduler.Reconcile
      end

      trigger :issue_invoice do
        action :issue_invoice
        read_action :read_global
        where expr(status == :paid and is_nil(invoiced_at))
        scheduler_cron "0 * * * *"
        max_attempts 3
        queue :billing_invoices

        worker_module_name Firmowid.Billing.Payment.Worker.IssueInvoice
        scheduler_module_name Firmowid.Billing.Payment.Scheduler.IssueInvoice
      end
    end
  end

  code_interface do
    define :destroy, action: :destroy
    define :list, action: :list
  end

  actions do
    defaults [:read]

    read :list do
      description "List the organization's payments, optionally only those in one status."
      argument :status, :atom, constraints: [one_of: @statuses]

      prepare build(filter: expr(status == ^arg(:status))) do
        where present(:status)
      end
    end

    read :read_global do
      description "Unscoped read for AshOban schedulers — reads across all organizations."
      multitenancy :allow_global
      pagination keyset?: true
    end

    read :by_id_global do
      description "Find a payment by id in any organization, for the Tpay notification that names only the payment."
      get? true
      multitenancy :allow_global
      argument :id, :uuid, allow_nil?: false
      filter expr(id == ^arg(:id))
    end

    create :create do
      description "Open a payment for a subscription's period, priced from the plan catalog; its first attempt falls on the period's first day."

      accept [
        :subscription_id,
        :kind,
        :plan,
        :billing_period,
        :period_start,
        :period_end,
        :max_attempts
      ]

      change PricePeriod

      change fn changeset, _context ->
        period_start = Ash.Changeset.get_attribute(changeset, :period_start)
        Ash.Changeset.force_change_attribute(changeset, :next_attempt_on, period_start)
      end
    end

    update :charge do
      description "Charge the subscription's card for the next attempt of a due payment, at most once per attempt."
      # The claim commits on its own before Tpay is asked.
      transaction? false
      require_atomic? false

      # Only one caller claims the attempt; the others find no due payment and fail as a stale record.
      change filter(expr(due?))
      change atomic_update(:attempts, expr(attempts + 1))
      # The transaction of an earlier attempt is no answer about this one.
      change set_attribute(:tpay_transaction_id, nil)
      change transition_state(:charging)
      change ChargeCard
    end

    update :release do
      description "Give back a claimed attempt that never reached Tpay, so it counts as never made."
      require_atomic? false

      change ReleaseClaim
    end

    update :record_outcome do
      description "Record what Tpay decided about a charge, asking Tpay when no outcome is given."
      require_atomic? false

      argument :outcome, :atom, constraints: [one_of: [:paid, :declined, :pending]]
      argument :transaction_id, :string
      argument :attempt, :integer, constraints: [min: 1]

      argument :paid_at, :utc_datetime_usec, description: "When Tpay booked the payment, for a paid outcome."

      change FetchOutcome
      change get_and_lock_for_update()
      change ApplyOutcome
      change SwitchUpgradedPlan, where: [attribute_equals(:kind, :upgrade)]
      # Only an unpaid period leaves the subscription unpaid; a declined upgrade keeps the plan
      # it had, and the admin who asked for it sees the outcome at once.
      change EndSubscriptionOnFailure, where: [attribute_equals(:kind, :period)]
      change FollowUpDecline
    end

    update :issue_invoice do
      description "Issue the advance invoice for a paid payment."
      require_atomic? false

      change IssueAdvanceInvoice
    end

    destroy :destroy do
      description "Delete a payment with its organization."
      primary? true
    end
  end

  policies do
    bypass [
      {SystemActorRole, roles: [:organization_cleanup]},
      action([:read, :list, :destroy])
    ] do
      authorize_if expr(not is_nil(^actor(:org_id)) and organization_id == ^actor(:org_id))
    end

    bypass AshObanInteraction do
      authorize_if always()
    end

    # The Tpay notification names only the payment, not the organization.
    bypass [{SystemActorRole, roles: [:billing]}, action(:by_id_global)] do
      authorize_if expr(is_nil(^actor(:org_id)))
    end

    # The role holds only inside its organization's tenant, so a payment it creates belongs there.
    bypass [{SystemActorRole, roles: [:billing]}, action(:create)] do
      authorize_if expr(not is_nil(^actor(:org_id)))
    end

    bypass [
      {SystemActorRole, roles: [:billing]},
      action([:read, :list, :charge, :release, :record_outcome])
    ] do
      authorize_if expr(not is_nil(^actor(:org_id)) and organization_id == ^actor(:org_id))
    end

    policy IsSystemActor do
      forbid_if always()
    end

    policy action([:read, :list]) do
      authorize_if {ActorRole, role: :admin}
    end
  end

  pub_sub do
    module Phoenix.PubSub
    name Firmowid.PubSub
    # The topic of the payment's subscription, where `CardReturn` waits for the first charge.
    prefix "subscription"
    transform fn _notification -> :payment_recorded end
    publish :record_outcome, [:_tenant]
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :kind, :atom,
      public?: true,
      allow_nil?: false,
      default: :period,
      constraints: [one_of: [:period, :upgrade]],
      description: "A billed period, or the price difference of an upgrade within one."

    attribute :plan, :atom,
      public?: true,
      allow_nil?: false,
      constraints: [one_of: Subscription.plans()]

    attribute :billing_period, :atom,
      public?: true,
      allow_nil?: false,
      constraints: [one_of: [:monthly, :yearly]]

    attribute :period_start, :date, public?: true, allow_nil?: false
    attribute :period_end, :date, public?: true, allow_nil?: false
    attribute :net_amount, :decimal, public?: true, allow_nil?: false
    attribute :gross_amount, :decimal, public?: true, allow_nil?: false

    attribute :vat_rate, :string,
      public?: true,
      allow_nil?: false,
      description: "The VAT rate in percent, as the advance invoice states it."

    attribute :status, :atom,
      public?: true,
      allow_nil?: false,
      default: :due,
      constraints: [one_of: @statuses]

    attribute :attempts, :integer,
      public?: true,
      allow_nil?: false,
      default: 0,
      description: "Charges claimed so far; the latest one is the current attempt."

    attribute :max_attempts, :integer,
      public?: true,
      allow_nil?: false,
      # One attempt day each, see `Firmowid.Billing.Payment.Changes.ApplyOutcome`.
      constraints: [min: 1, max: 3],
      description: "Charges tried before the payment fails and its subscription ends."

    attribute :next_attempt_on, :date, public?: true, allow_nil?: false

    attribute :tpay_transaction_id, :string,
      public?: true,
      description:
        "Title (`TR-…`) of the Tpay transaction of the current attempt, once Tpay answered, or of the attempt that paid."

    attribute :paid_at, :utc_datetime_usec, public?: true
    attribute :invoiced_at, :utc_datetime_usec, public?: true

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :organization, Firmowid.Core.Organization do
      allow_nil? false
    end

    belongs_to :subscription, Subscription do
      public? true
      allow_nil? false
    end
  end

  calculations do
    # Days are Polish days, as `Firmowid.LocalDate` counts them; the database clock runs in UTC.
    calculate :due?,
              :boolean,
              expr(
                status in [:due, :declined] and
                  next_attempt_on <= fragment("(now() AT TIME ZONE 'Europe/Warsaw')::date") and
                  exists(subscription, status == :active)
              )

    # The period as the card charge and the advance invoice name it, e.g. "01.12.2026–31.12.2026".
    calculate :period_label,
              :string,
              expr(
                fragment(
                  "to_char(?, 'DD.MM.YYYY') || '–' || to_char(?, 'DD.MM.YYYY')",
                  period_start,
                  period_end
                )
              )
  end

  aggregates do
    # Tpay requires the payer's email; the owner is the organization's contact. The charge runs as
    # the billing system actor, which reads no user accounts.
    first :payer_email, [:organization, :owner], :email do
      authorize? false
    end
  end

  identities do
    identity :one_per_period, [:subscription_id, :kind, :period_start] do
      where expr(status != :failed)
    end
  end
end
