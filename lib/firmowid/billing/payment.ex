# The primary read serves relationships; `:read_global` and `:issue_invoice` run only from AshOban triggers.
# credo:disable-for-this-file AshCredo.Check.Design.MissingCodeInterface
defmodule Firmowid.Billing.Payment do
  @moduledoc """
  A paid Stripe invoice the organization (the row's tenant) issues an advance invoice (KSeF ZAL)
  for. The row holds only the Stripe invoice's id and whether the invoice was issued; amounts,
  period and buyer are read from Stripe when it is issued, so the same mechanism serves any
  organization whose Stripe payments Firmowid invoices. Its id becomes the id of the invoice.
  """

  use Ash.Resource,
    domain: Firmowid.Billing,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshOban]

  alias AshOban.Checks.AshObanInteraction
  alias Firmowid.Billing.Payment.Changes.IssueAdvanceInvoice
  alias Firmowid.Checks.IsSystemActor
  alias Firmowid.Checks.SystemActorRole
  alias Firmowid.Resource

  require Resource

  postgres do
    table "billing_payments"
    repo Firmowid.Repo
  end

  oban do
    use_tenant_from_record? true

    triggers do
      trigger :issue_invoice do
        action :issue_invoice
        read_action :read_global
        where expr(is_nil(invoiced_at))
        scheduler_cron "0 * * * *"
        max_attempts 3
        queue :billing

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
      description "List the organization's payments."
    end

    read :read_global do
      description "Unscoped read for AshOban schedulers — reads across all organizations."
      multitenancy :allow_global
      pagination keyset?: true
    end

    create :record do
      description "Remember a paid Stripe invoice once; its advance invoice follows."
      accept [:stripe_invoice_id]

      # The same invoice delivered again returns the payment recorded first.
      upsert? true
      upsert_identity :unique_stripe_invoice_id
      upsert_fields []
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

    # The role holds only inside its organization's tenant, so a payment it records belongs there.
    bypass [{SystemActorRole, roles: [:billing]}, action(:record)] do
      authorize_if expr(not is_nil(^actor(:org_id)))
    end

    policy IsSystemActor do
      forbid_if always()
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :stripe_invoice_id, :string,
      public?: true,
      allow_nil?: false,
      description: "The paid Stripe invoice."

    attribute :invoiced_at, :utc_datetime_usec, public?: true

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :organization, Firmowid.Core.Organization do
      allow_nil? false
    end
  end

  identities do
    identity :unique_stripe_invoice_id, [:stripe_invoice_id] do
      all_tenants? true
    end
  end
end
