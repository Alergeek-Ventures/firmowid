defmodule Firmowid.Ash.Invoicing.KsefInvoiceDigest do
  @moduledoc """
  Persisted digest of KSeF cost invoices created in Firmowid.
  """
  use Ash.Resource,
    domain: Firmowid.Ash.Invoicing,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshOban]

  alias AshOban.Checks.AshObanInteraction
  alias Firmowid.Ash.Checks.SystemActorRole
  alias Firmowid.Ash.Invoicing.Actions.CreateScheduledKsefInvoiceDigests
  alias Firmowid.Ash.Invoicing.Changes.SendKsefInvoiceDigest
  alias Firmowid.Ash.Invoicing.Changes.VerifyKsefInvoiceDigestCreate
  alias Firmowid.Ash.Invoicing.KsefInvoiceDigestItem
  alias Firmowid.Ash.Resource

  require Resource

  postgres do
    table "ksef_invoice_digests"
    repo Firmowid.Repo
  end

  oban do
    use_tenant_from_record? true

    scheduled_actions do
      schedule :create_scheduled_digests, "0 9,15 * * 1-5" do
        action :create_scheduled_digests
        queue :default
        worker_module_name Firmowid.Ash.Invoicing.KsefInvoiceDigest.Worker.CreateScheduledDigests
      end
    end

    triggers do
      trigger :send_digest do
        action :send_digest
        read_action :read_global
        worker_read_action :read_for_delivery
        where expr(is_nil(delivered_at))
        scheduler_cron false
        max_attempts 3
        queue :default

        worker_module_name Firmowid.Ash.Invoicing.KsefInvoiceDigest.Worker.SendDigest
        scheduler_module_name Firmowid.Ash.Invoicing.KsefInvoiceDigest.Scheduler.SendDigest
      end
    end
  end

  code_interface do
    define :read, action: :read
    define :read_global, action: :read_global
    define :read_for_delivery, action: :read_for_delivery
    define :create_digest, action: :create_digest
    define :create_scheduled_digests, action: :create_scheduled_digests
    define :send_digest, action: :send_digest
  end

  actions do
    defaults [:read]

    read :read_global do
      description "Unscoped read for AshOban digest delivery."
      multitenancy :allow_global
      pagination keyset?: true
    end

    read :read_for_delivery do
      description "Load a digest with all data required for email delivery."
      prepare build(load: [:organization, :cost_invoices])
    end

    create :create_digest do
      description "Create a KSeF digest from a set of cost invoices."
      accept []

      argument :cost_invoice_ids, {:array, :uuid}, allow_nil?: false

      change manage_relationship(:cost_invoice_ids, :cost_invoices,
               type: :append,
               value_is_key: :id
             )

      change VerifyKsefInvoiceDigestCreate
    end

    update :send_digest do
      description "Send a prepared KSeF digest to recipient admins."
      require_atomic? false
      accept []
      argument :admin_user_ids, {:array, :uuid}
      change SendKsefInvoiceDigest
    end

    action :create_scheduled_digests, :integer do
      description "Builds KSeF cost-invoice digests for all currently eligible undigested invoices."
      argument :organization_ids, {:array, :uuid}
      argument :enqueue_send?, :boolean, allow_nil?: false, default: true
      run CreateScheduledKsefInvoiceDigests
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if {Firmowid.Ash.Checks.AtLeastRole, role: :accountant}
      authorize_if {SystemActorRole, roles: [:ksef_digest]}
    end

    policy action(:create_scheduled_digests) do
      authorize_if AshObanInteraction
      authorize_if {SystemActorRole, roles: [:ksef_digest]}
    end

    policy action([:read_for_delivery, :create_digest, :send_digest]) do
      authorize_if {SystemActorRole, roles: [:ksef_digest]}
    end

    policy action(:read_global) do
      authorize_if {SystemActorRole, roles: [:ksef_digest]}
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :delivered_at, :utc_datetime, public?: true

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :organization, Firmowid.Ash.Core.Organization do
      allow_nil? false
    end

    has_many :digest_items, KsefInvoiceDigestItem do
      source_attribute :id
      destination_attribute :digest_id
    end

    many_to_many :cost_invoices, Firmowid.Ash.Invoicing.CostInvoice do
      through KsefInvoiceDigestItem
      could_be_related_at_creation? true
      source_attribute_on_join_resource :digest_id
      destination_attribute_on_join_resource :cost_invoice_id
    end
  end

  aggregates do
    count :invoice_count, :digest_items
  end
end
