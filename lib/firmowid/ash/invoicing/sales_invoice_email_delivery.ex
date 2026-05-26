defmodule Firmowid.Ash.Invoicing.SalesInvoiceEmailDelivery do
  @moduledoc false

  use Ash.Resource,
    otp_app: :firmowid,
    domain: Firmowid.Ash.Invoicing,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Checks.IsSystemActor
  alias Firmowid.Ash.Checks.SystemActorRole
  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Resource

  require Resource

  postgres do
    table "sales_invoice_email_deliveries"
    repo Firmowid.Repo

    custom_indexes do
      index [:organization_id, :sales_invoice_id]
    end
  end

  actions do
    defaults [:read]

    create :record_delivery do
      description "Persist a sales invoice email delivery outcome."

      accept [
        :sales_invoice_id,
        :delivery_type,
        :status,
        :recipient_email,
        :resend_email_id,
        :error_message,
        :sent_at,
        :failed_at
      ]
    end

    action :send_for_invoice, :struct do
      description "Send a sales invoice email and persist the delivery outcome."

      argument :sales_invoice_id, :uuid_v7, allow_nil?: false

      argument :delivery_type, :atom,
        allow_nil?: false,
        constraints: [one_of: [:basic, :reminder, :invoice_correction]]

      run Firmowid.Ash.Invoicing.Actions.SendSalesInvoiceEmail
    end
  end

  policies do
    # sales_invoice_processor: full access for background email jobs
    bypass {SystemActorRole, roles: [:sales_invoice_processor]} do
      authorize_if action_type(:read)
      authorize_if action(:record_delivery)
      authorize_if action(:send_for_invoice)
    end

    # Allowed when loading through a SalesInvoice relationship.
    # Covers timeline rendering in the UI — users never read deliveries directly.
    policy accessing_from(SalesInvoice, :email_deliveries) do
      authorize_if always()
    end

    # Other system actors: explicitly denied
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

    attribute :delivery_type, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: [:basic, :reminder, :invoice_correction]]

    attribute :status, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: [:sent, :failed]]

    attribute :recipient_email, :string, public?: true
    attribute :resend_email_id, :string, public?: true
    attribute :error_message, :string, public?: true
    attribute :sent_at, :utc_datetime, public?: true
    attribute :failed_at, :utc_datetime, public?: true

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :sales_invoice, SalesInvoice do
      allow_nil? false
      attribute_writable? true
    end

    belongs_to :organization, Firmowid.Ash.Core.Organization do
      allow_nil? false
    end
  end
end
