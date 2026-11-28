# The primary read serves relationships; `:read_global`, `:issue_invoice` and `:fail` run only from AshOban triggers.
# credo:disable-for-this-file AshCredo.Check.Design.MissingCodeInterface
defmodule Firmowid.Invoicing.StripePayment do
  @moduledoc """
  A successful payment in the company's connected Stripe account (one payment intent), which
  gets one invoice however many Stripe events report it.

  `Firmowid.Invoicing.StripeConnection` records it; the `:issue_invoice` trigger then reads it
  from Stripe (`InvoiceInput`) and issues its invoice, which takes the payment's id. A buyer
  without a tax ID is skipped when the company does not invoice private persons, and a VAT
  payer's payment with a line Stripe charged no tax on is marked untaxed: Firmowid does not
  guess a VAT rate. A payment whose invoice still fails after the last attempt is marked failed with the reason, so the
  company sees it instead of an invoice.
  """

  use Ash.Resource,
    domain: Firmowid.Invoicing,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshOban]

  alias AshOban.Checks.AshObanInteraction
  alias Firmowid.Checks.ActorRole
  alias Firmowid.Checks.SystemActorRole
  alias Firmowid.Invoicing.StripePayment.Changes.IssueInvoice
  alias Firmowid.Resource

  require Resource

  postgres do
    table "stripe_payments"
    repo Firmowid.Repo

    references do
      reference :organization, on_delete: :delete
    end
  end

  oban do
    use_tenant_from_record? true

    triggers do
      trigger :issue_invoice do
        action :issue_invoice
        read_action :read_global
        where expr(status == :pending)
        # Recording runs it at once; the hourly run picks up what was recorded while Stripe or
        # KSeF did not answer.
        scheduler_cron "0 * * * *"
        max_attempts 3
        on_error :fail
        queue :invoicing

        worker_module_name Firmowid.Invoicing.StripePayment.Worker.IssueInvoice
        scheduler_module_name Firmowid.Invoicing.StripePayment.Scheduler.IssueInvoice
      end
    end
  end

  actions do
    defaults [:read]

    read :list do
      description "The organization's latest Stripe payments with their invoices, newest first."
      pagination offset?: true, default_limit: 10
      prepare build(sort: [paid_at: :desc], load: [:sales_invoice])
    end

    read :read_global do
      description "Unscoped read for AshOban schedulers — reads across all organizations."
      multitenancy :allow_global
      pagination keyset?: true
    end

    create :record do
      description "Remember a successful Stripe payment once; its invoice follows."
      accept [:payment_intent_id, :paid_at, :amount, :currency]

      # The same payment reported again returns the one recorded first.
      upsert? true
      upsert_identity :unique_payment_intent
      upsert_fields []

      change run_oban_trigger(:issue_invoice)
    end

    update :issue_invoice do
      description "Issue the invoice of a recorded payment, or skip a private person's."
      primary? true
      require_atomic? false
      change IssueInvoice
    end

    update :fail do
      description "Mark a payment whose invoice failed after the last attempt."
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

    # Recording a refund reads the payments it refunds.
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

    attribute :payment_intent_id, :string do
      allow_nil? false
      public? true
      description "The Stripe payment intent."
    end

    attribute :paid_at, :utc_datetime do
      allow_nil? false
      public? true
    end

    attribute :amount, :decimal do
      allow_nil? false
      public? true
      description "What Stripe took, in the currency's main unit."
    end

    attribute :currency, :string do
      allow_nil? false
      public? true
    end

    attribute :status, :atom do
      allow_nil? false
      default :pending
      public? true
      constraints one_of: [:pending, :invoiced, :skipped, :untaxed, :failed]
    end

    attribute :error, :string do
      public? true
      description "Why the invoice could not be issued."
    end

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :organization, Firmowid.Core.Organization do
      allow_nil? false
    end

    has_one :sales_invoice, Firmowid.Invoicing.SalesInvoice do
      public? true
      source_attribute :id
      destination_attribute :id
      description "The invoice issued for the payment."
    end
  end

  identities do
    identity :unique_payment_intent, [:organization_id, :payment_intent_id]
  end
end
