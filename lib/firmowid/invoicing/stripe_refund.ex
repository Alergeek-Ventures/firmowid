# The primary read serves relationships; `:read_global`, `:correct_invoice` and `:fail` run only from AshOban triggers.
# credo:disable-for-this-file AshCredo.Check.Design.MissingCodeInterface
defmodule Firmowid.Invoicing.StripeRefund do
  @moduledoc """
  A refund in the company's connected Stripe account of a payment the integration recorded
  (`Firmowid.Invoicing.StripePayment`), which gets one correction of the payment's invoice
  however many Stripe events report it.

  `Firmowid.Invoicing.StripeConnection` records it; the `:correct_invoice` trigger waits until
  the payment's invoice is settled and accepted by KSeF, then corrects it (`CorrectInvoice`).
  A correction takes the refund's id. A refund the integration cannot correct by itself, such
  as a partial refund without a Stripe credit note, is marked `:manual` with the reason, and one
  of a payment that got no invoice because the buyer gave no tax ID is `:skipped`. A refund
  whose correction still fails after the last attempt is marked failed with the reason.
  """

  use Ash.Resource,
    domain: Firmowid.Invoicing,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshOban]

  alias AshOban.Checks.AshObanInteraction
  alias Firmowid.Checks.ActorRole
  alias Firmowid.Checks.SystemActorRole
  alias Firmowid.Invoicing.StripeRefund.Changes.CorrectInvoice
  alias Firmowid.Resource

  require Resource

  postgres do
    table "stripe_refunds"
    repo Firmowid.Repo

    references do
      reference :organization, on_delete: :delete
    end
  end

  oban do
    use_tenant_from_record? true

    triggers do
      trigger :correct_invoice do
        action :correct_invoice
        read_action :read_global
        # A correction needs its invoice in KSeF, which takes a while after the payment; a
        # payment that is not invoiced (and will not be) is settled at once.
        where expr(
                status == :pending and
                  (stripe_payment.status in [:skipped, :untaxed, :failed] or
                     (stripe_payment.status == :invoiced and
                        not is_nil(stripe_payment.sales_invoice.ksef_number)))
              )

        scheduler_cron "*/15 * * * *"
        max_attempts 3
        on_error :fail
        queue :invoicing

        worker_module_name Firmowid.Invoicing.StripeRefund.Worker.CorrectInvoice
        scheduler_module_name Firmowid.Invoicing.StripeRefund.Scheduler.CorrectInvoice
      end
    end
  end

  actions do
    defaults [:read]

    read :list do
      description "The organization's latest Stripe refunds with their corrections, newest first."
      pagination offset?: true, default_limit: 10
      prepare build(sort: [refunded_at: :desc], load: [:sales_invoice])
    end

    read :read_global do
      description "Unscoped read for AshOban schedulers — reads across all organizations."
      multitenancy :allow_global
      pagination keyset?: true
    end

    create :record do
      description "Remember a refund of a recorded Stripe payment once; its correction follows."
      accept [:refund_id, :payment_intent_id, :refunded_at, :amount, :currency]

      # The same refund reported again returns the one recorded first.
      upsert? true
      upsert_identity :unique_refund
      upsert_fields []

      change run_oban_trigger(:correct_invoice)
    end

    update :correct_invoice do
      description "Correct the invoice of the refunded payment, or mark why it is not corrected."
      primary? true
      require_atomic? false
      change CorrectInvoice
    end

    update :fail do
      description "Mark a refund whose correction failed after the last attempt."
      require_atomic? false
      argument :error, :term, allow_nil?: false
      change set_attribute(:status, :failed)
      # The reasons only, without the class error's bread crumbs and stack trace.
      change fn changeset, _context ->
        %{errors: errors} =
          changeset |> Ash.Changeset.get_argument(:error) |> Ash.Error.to_error_class()

        reason = Enum.map_join(errors, " ", &(&1 |> Exception.message() |> String.trim()))
        Ash.Changeset.force_change_attribute(changeset, :error, reason)
      end
    end
  end

  policies do
    bypass AshObanInteraction do
      authorize_if always()
    end

    bypass [{SystemActorRole, roles: [:stripe_invoicing]}, action([:record, :read])] do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if {ActorRole, role: :admin}
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :refund_id, :string do
      allow_nil? false
      public? true
      description "The Stripe refund."
    end

    attribute :payment_intent_id, :string do
      allow_nil? false
      public? true
      description "The refunded Stripe payment intent."
    end

    attribute :refunded_at, :utc_datetime do
      allow_nil? false
      public? true
    end

    attribute :amount, :decimal do
      allow_nil? false
      public? true
      description "What Stripe returned, in the currency's main unit."
    end

    attribute :currency, :string do
      allow_nil? false
      public? true
    end

    attribute :status, :atom do
      allow_nil? false
      default :pending
      public? true
      constraints one_of: [:pending, :corrected, :skipped, :manual, :failed]
    end

    attribute :manual_reason, :atom do
      public? true
      constraints one_of: [:no_invoice, :no_credit_note, :credit_note_lines]

      description "Why a `:manual` refund is left to the company: the payment got no invoice from Firmowid, " <>
                    "a partial refund has no Stripe credit note, or its note credits lines the invoice does not have."
    end

    attribute :error, :string do
      public? true
      description "Why the correction failed."
    end

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :organization, Firmowid.Core.Organization do
      allow_nil? false
    end

    has_one :stripe_payment, Firmowid.Invoicing.StripePayment do
      public? true
      source_attribute :payment_intent_id
      destination_attribute :payment_intent_id
      # One Stripe account can be connected to two companies.
      filter expr(organization_id == parent(organization_id))
      description "The refunded payment."
    end

    has_one :sales_invoice, Firmowid.Invoicing.SalesInvoice do
      public? true
      source_attribute :id
      destination_attribute :id
      description "The correction issued for the refund."
    end
  end

  identities do
    identity :unique_refund, [:organization_id, :refund_id]
  end
end
