# Every update is a lifecycle step with side effects, so none is a safe primary.
# credo:disable-for-this-file AshCredo.Check.Design.MissingPrimaryAction
# The primary read only serves the organization's subscriptions relationship and its aggregates.
# credo:disable-for-this-file AshCredo.Check.Design.MissingCodeInterface
defmodule Firmowid.Billing.Subscription do
  @moduledoc """
  A paid plan an organization bought with a card saved at Tpay, one row per purchase.

  `:start` opens Tpay's card page and leaves the row `:awaiting_card`; the tokenization
  notification runs `:save_card`, which activates it, opens its first period and sets the
  organization's plan. The first period is the organization's free month once, unless it had
  a trial; after that it is paid at once. `:renew` opens each next period with the payment for
  it, and `:end` stops the charges. At most one subscription per organization is not `:ended`.

  An active subscription moves to a more expensive plan with `:upgrade`, which charges the price
  difference first, and replaces its card with `:change_card`, which opens Tpay's card page
  again; that card's notification runs `:save_card` too.
  """

  use Ash.Resource,
    domain: Firmowid.Billing,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshStateMachine, AshOban],
    notifiers: [Ash.Notifier.PubSub]

  alias AshOban.Checks.AshObanInteraction
  alias Firmowid.Billing.Payment
  alias Firmowid.Billing.PlanCatalog
  alias Firmowid.Billing.Subscription.Calculations.UpgradePrice
  alias Firmowid.Billing.Subscription.Changes.OpenPeriod
  alias Firmowid.Billing.Subscription.Changes.RequestCardPage
  alias Firmowid.Billing.Subscription.Changes.ReturnOrganizationToFree
  alias Firmowid.Billing.Subscription.Changes.SetOrganizationPlan
  alias Firmowid.Billing.Subscription.Changes.Upgrade
  alias Firmowid.Billing.Subscription.Validations.OrganizationCanBuy
  alias Firmowid.Billing.Subscription.Validations.PeriodSettled
  alias Firmowid.Checks.ActorRole
  alias Firmowid.Checks.IsSystemActor
  alias Firmowid.Checks.SystemActorRole
  alias Firmowid.Resource

  require Resource

  @plans Enum.reject(
           PlanCatalog.plans(),
           &Decimal.eq?(PlanCatalog.plan!(&1).monthly_price_pln, 0)
         )

  # A plan set by hand ends the subscription for another plan; the last declined charge ends it unpaid.
  @end_reasons [:plan_changed, :payment_failed]

  @doc "Returns the plans a subscription can buy: the paid ones."
  @spec plans() :: [PlanCatalog.plan()]
  def plans, do: @plans

  postgres do
    table "billing_subscriptions"
    repo Firmowid.Repo

    identity_wheres_to_sql one_open_per_organization: "status != 'ended'"
  end

  state_machine do
    state_attribute :status
    initial_states [:awaiting_card]
    default_initial_state :awaiting_card

    transitions do
      # A later card replaces the card of the active subscription.
      transition :save_card, from: [:awaiting_card, :active], to: :active
      transition :end, from: [:awaiting_card, :active], to: :ended
    end
  end

  oban do
    use_tenant_from_record? true

    triggers do
      trigger :renew do
        action :renew
        read_action :read_global
        where expr(renewal_due?)
        scheduler_cron "0 6 * * *"
        max_attempts 3
        queue :billing_renewals

        worker_module_name Firmowid.Billing.Subscription.Worker.Renew
        scheduler_module_name Firmowid.Billing.Subscription.Scheduler.Renew
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
      description "List the organization's subscriptions, optionally only those in one status."
      argument :status, :atom, constraints: [one_of: [:awaiting_card, :active, :ended]]

      prepare build(filter: expr(status == ^arg(:status))) do
        where present(:status)
      end
    end

    read :read_global do
      description "Unscoped read for AshOban schedulers — reads across all organizations."
      multitenancy :allow_global
      pagination keyset?: true
    end

    read :by_tokenization_id do
      description "Find the subscription whose latest card page a Tpay tokenization belongs to, in any organization."
      get? true
      multitenancy :allow_global
      argument :tokenization_id, :string, allow_nil?: false
      # An ended subscription takes no card; a notification of an older card page finds nothing.
      filter expr(tokenization_id == ^arg(:tokenization_id) and status in [:awaiting_card, :active])
    end

    create :start do
      description "Open Tpay's card page for a paid plan, reusing the organization's subscription that still awaits a card."
      accept [:plan, :billing_period]
      # No database transaction is held open while Tpay answers.
      transaction? false

      upsert? true
      upsert_identity :one_open_per_organization
      upsert_fields [:plan, :billing_period, :tokenization_id, :updated_at]
      # An active subscription is never replaced; the conflict comes back as a stale record.
      upsert_condition expr(status == :awaiting_card)

      validate OrganizationCanBuy
      change RequestCardPage

      metadata :card_page_url, :string, allow_nil?: false
    end

    update :save_card do
      description "Store the card Tpay tokenized on the subscription's latest card page. The first card activates the subscription, opens its first period and gives the organization the plan; a later one only replaces the card."
      require_atomic? false

      argument :tokenization_id, :string, allow_nil?: false
      argument :card_token, :string, allow_nil?: false, sensitive?: true
      argument :card_brand, :string
      argument :card_tail, :string
      argument :card_expires, :string

      # Only the row still naming this tokenization and still in the status it was read in is
      # updated, so a concurrent repeat of the first card fails as a stale record instead of
      # activating twice. A repeated replacement saves the same card again.
      change filter(expr(tokenization_id == ^arg(:tokenization_id)))

      change filter(expr(status == :awaiting_card)),
        where: [data_one_of(:status, [:awaiting_card])]

      change filter(expr(status == :active)), where: [data_one_of(:status, [:active])]
      change transition_state(:active)
      change set_attribute(:card_token, arg(:card_token))
      change set_attribute(:card_brand, arg(:card_brand))
      change set_attribute(:card_tail, arg(:card_tail))
      change set_attribute(:card_expires, arg(:card_expires))

      # The first card only.
      change set_attribute(:activated_at, &DateTime.utc_now/0),
        where: [data_one_of(:status, [:awaiting_card])]

      # A paid first period has one attempt: a declined card ends the subscription at once.
      change {OpenPeriod, attempts: 1, charge_at_once?: true},
        where: [data_one_of(:status, [:awaiting_card])]

      change SetOrganizationPlan, where: [data_one_of(:status, [:awaiting_card])]
    end

    update :change_card do
      description "Open Tpay's card page to replace the card of the active subscription; the card is replaced once Tpay's notification of that page arrives."
      # No database transaction is held open while Tpay answers.
      transaction? false
      require_atomic? false

      change filter(expr(status == :active))
      change {RequestCardPage, saved: "zmieniona", failed: "niezmieniona"}

      metadata :card_page_url, :string, allow_nil?: false
    end

    update :upgrade do
      description "Move the active subscription to a more expensive plan at once, charging the price difference for the rest of the paid period first; see `Changes.Upgrade`."
      require_atomic? false

      argument :plan, :atom, allow_nil?: false, constraints: [one_of: @plans]

      change filter(expr(status == :active))
      # Checked on the locked row, so a renewal opening an unpaid period either commits first
      # and refuses the upgrade, or waits for it.
      change get_and_lock_for_update()
      validate PeriodSettled, before_action?: true
      change Upgrade

      metadata :upgrade_payment, :struct, constraints: [instance_of: Payment]
    end

    update :switch_plan do
      description "Give the active subscription and its organization a plan whose price difference is paid."
      require_atomic? false
      accept [:plan]

      change filter(expr(status == :active))
      change SetOrganizationPlan
    end

    update :renew do
      description "Open the next period and the payment for it once its charge date comes."
      require_atomic? false

      # A repeated renewal finds the charge date moved on and fails as a stale record.
      change filter(expr(renewal_due?))
      # Priced from the row as it is once locked, so an upgrade committing meanwhile is billed.
      change get_and_lock_for_update()
      change {OpenPeriod, attempts: 3}
    end

    update :end do
      description "End the subscription; nothing is charged for it any more."
      argument :reason, :atom, allow_nil?: false, constraints: [one_of: @end_reasons]

      change filter(expr(status != :ended))
      change transition_state(:ended)
      change set_attribute(:ended_at, &DateTime.utc_now/0)
      change set_attribute(:end_reason, arg(:reason))
      change set_attribute(:next_charge_on, nil)
      change ReturnOrganizationToFree, where: [argument_equals(:reason, :payment_failed)]
    end

    destroy :destroy do
      description "Delete a subscription with its organization."
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

    # The Tpay notification names only the tokenization, not the organization.
    bypass [{SystemActorRole, roles: [:billing]}, action(:by_tokenization_id)] do
      authorize_if expr(is_nil(^actor(:org_id)))
    end

    bypass AshObanInteraction do
      authorize_if always()
    end

    bypass [
      {SystemActorRole, roles: [:billing]},
      action([:read, :list, :save_card, :switch_plan, :end])
    ] do
      authorize_if expr(not is_nil(^actor(:org_id)) and organization_id == ^actor(:org_id))
    end

    policy IsSystemActor do
      forbid_if always()
    end

    policy action([:read, :list, :start, :change_card, :upgrade]) do
      authorize_if {ActorRole, role: :admin}
    end
  end

  pub_sub do
    module Phoenix.PubSub
    name Firmowid.PubSub
    prefix "subscription"
    # A bare marker: the record holds the decrypted card token. The subscriber reads what changed.
    transform fn _notification -> :subscription_changed end
    publish :save_card, [:_tenant]
    publish :end, [:_tenant]
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :plan, :atom, public?: true, allow_nil?: false, constraints: [one_of: @plans]

    attribute :billing_period, :atom,
      public?: true,
      allow_nil?: false,
      constraints: [one_of: [:monthly, :yearly]]

    attribute :status, :atom,
      public?: true,
      allow_nil?: false,
      default: :awaiting_card,
      constraints: [one_of: [:awaiting_card, :active, :ended]]

    attribute :tokenization_id, :string,
      public?: true,
      allow_nil?: false,
      description: "Tpay's id of the card page opened last, which its notification names."

    attribute :card_token, Firmowid.Ksef.EncryptedBinaryType do
      sensitive? true
      public? false
      description "Tpay's token of the saved card, which recurring charges use."
    end

    attribute :card_brand, :string, public?: true

    attribute :card_tail, :string,
      public?: true,
      description: "The last digits of the card number."

    attribute :card_expires, :string,
      public?: true,
      description: "The card's expiry as Tpay sends it, MMYY."

    attribute :activated_at, :utc_datetime_usec,
      public?: true,
      description: "When the card was saved; the first activation used the organization's free month."

    attribute :current_period_start, :date, public?: true
    attribute :current_period_end, :date, public?: true
    attribute :next_charge_on, :date, public?: true
    attribute :ended_at, :utc_datetime_usec, public?: true
    attribute :end_reason, :atom, public?: true, constraints: [one_of: @end_reasons]

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :organization, Firmowid.Core.Organization do
      allow_nil? false
    end

    has_many :payments, Payment
  end

  calculations do
    # Days are Polish days, as `Firmowid.LocalDate` counts them; the database clock runs in UTC.
    calculate :renewal_due?,
              :boolean,
              expr(
                status == :active and
                  next_charge_on <= fragment("(now() AT TIME ZONE 'Europe/Warsaw')::date")
              )

    # Nothing is charged for the current period: the organization's free month.
    calculate :current_period_free?,
              :boolean,
              expr(
                not exists(
                  payments,
                  kind == :period and period_start == parent(current_period_start)
                )
              )

    # Nothing is owed for the current period: it is free or its payment is paid.
    calculate :current_period_settled?,
              :boolean,
              expr(
                not exists(
                  payments,
                  kind == :period and period_start == parent(current_period_start) and
                    status != :paid
                )
              )

    calculate :upgrade_price, :map, UpgradePrice do
      description "What moving to a more expensive plan costs now, `%{net_amount, gross_amount}`."
      argument :plan, :atom, allow_nil?: false, constraints: [one_of: @plans]
    end
  end

  identities do
    identity :one_open_per_organization, [:organization_id] do
      where expr(status != :ended)
    end

    identity :unique_tokenization_id, [:tokenization_id] do
      all_tenants? true
    end
  end
end
