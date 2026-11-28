# The primary read serves relationships; `:read_global` and `:fetch_payments` run only from AshOban triggers.
# credo:disable-for-this-file AshCredo.Check.Design.MissingCodeInterface
defmodule Firmowid.Invoicing.StripeConnection do
  @moduledoc """
  The company's Stripe account, whose successful payments Firmowid invoices.

  An admin connects it with a restricted Stripe key that only reads (`Changes.VerifyKey` names
  the permissions), and only while the company is connected to KSeF. Production takes only a
  live key (`rk_live_`); development and tests also take a test key (`rk_test_`), which then
  works exactly like a live one.

  Every five minutes `:fetch_payments` reads the `payment_intent.succeeded` and
  `charge.refunded` events since the last check. It records each payment as a
  `Firmowid.Invoicing.StripePayment`, which issues its invoice, and each refund of a recorded
  payment as a `Firmowid.Invoicing.StripeRefund`, which corrects that invoice. Payments from
  before the connection get no invoice. Disconnecting deletes the key; issued invoices and
  recorded payments and refunds stay.
  """

  use Ash.Resource,
    domain: Firmowid.Invoicing,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshOban]

  alias AshOban.Checks.AshObanInteraction
  alias Firmowid.Checks.ActorRole
  alias Firmowid.Checks.SystemActorRole
  alias Firmowid.Invoicing.StripeConnection.Changes.FetchPayments
  alias Firmowid.Invoicing.StripeConnection.Changes.VerifyKey
  alias Firmowid.Invoicing.Validations.KsefConnected
  alias Firmowid.Resource

  require Resource

  postgres do
    table "stripe_connections"
    repo Firmowid.Repo

    references do
      reference :organization, on_delete: :delete
    end
  end

  # The key reads the company's Stripe account, so only the work that uses it may read it.
  field_policies do
    private_fields :include

    field_policy :api_key do
      authorize_if AshObanInteraction
      authorize_if {SystemActorRole, roles: [:stripe_invoicing]}
    end

    field_policy :* do
      authorize_if always()
    end
  end

  oban do
    use_tenant_from_record? true

    triggers do
      trigger :fetch_payments do
        action :fetch_payments
        read_action :read_global
        scheduler_cron "*/5 * * * *"
        # The next run reads the same events again, so a failed one is not retried.
        max_attempts 1
        queue :invoicing

        worker_module_name Firmowid.Invoicing.StripeConnection.Worker.FetchPayments
        scheduler_module_name Firmowid.Invoicing.StripeConnection.Scheduler.FetchPayments
      end
    end
  end

  actions do
    defaults [:read]

    read :current do
      description "The organization's Stripe connection, or nil."
      get? true
    end

    read :read_global do
      description "Unscoped read for AshOban schedulers — reads across all organizations."
      multitenancy :allow_global
      pagination keyset?: true
    end

    create :connect do
      description "Connect the company's Stripe account with a restricted key; payments from now on get invoices."
      accept []

      argument :api_key, :string do
        allow_nil? false
        sensitive? true
        description "A restricted Stripe key with the read permissions the page lists."
      end

      # After authorization: the KSeF status is read with the actor's scope, which only an
      # admin's passes.
      validate KsefConnected, before_action?: true
      change VerifyKey
      change set_attribute(:events_since, &DateTime.utc_now/0)
    end

    update :set_invoice_consumers do
      description "Choose whether buyers without a tax ID get an invoice; applies to the next payments."
      primary? true
      accept [:invoice_consumers]
    end

    update :fetch_payments do
      description "Record the payments and refunds Stripe reported since the last check."
      require_atomic? false
      change FetchPayments
    end

    destroy :disconnect do
      description "Disconnect Stripe and delete its key. Issued invoices stay."
      primary? true
    end
  end

  policies do
    bypass AshObanInteraction do
      authorize_if always()
    end

    bypass [{SystemActorRole, roles: [:stripe_invoicing]}, action_type(:read)] do
      authorize_if always()
    end

    policy always() do
      authorize_if {ActorRole, role: :admin}
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :api_key, Firmowid.Ksef.EncryptedBinaryType do
      allow_nil? false
      sensitive? true
      description "The restricted Stripe key, encrypted."
    end

    attribute :invoice_consumers, :boolean do
      allow_nil? false
      default true
      public? true
      description "Whether a buyer without a tax ID gets an invoice as a private person."
    end

    attribute :events_since, :utc_datetime do
      allow_nil? false
      public? true
      description "Payments Stripe reported from this moment on are still to be read."
    end

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :organization, Firmowid.Core.Organization do
      allow_nil? false
    end
  end

  identities do
    identity :unique_organization, [:organization_id]
  end
end
