defmodule Firmowid.Invoicing.SkippedKsefSalesInvoice do
  @moduledoc """
  A sales invoice stored in KSeF that the import could not record yet.

  The import records one for each invoice it skips, so the organization sees which of its
  invoices are missing while engineers fix the cause, and removes it once a later import
  records the invoice. `reason` is the technical cause, for engineers.
  """

  use Ash.Resource,
    otp_app: :firmowid,
    domain: Firmowid.Invoicing,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Checks.AtLeastRole
  alias Firmowid.Checks.IsSystemActor
  alias Firmowid.Checks.SystemActorRole
  alias Firmowid.Resource

  require Resource

  postgres do
    table "skipped_ksef_sales_invoices"
    repo Firmowid.Repo
  end

  code_interface do
    define :read, action: :read
    define :list, action: :list
    define :destroy, action: :destroy
  end

  actions do
    defaults [:read]

    read :list do
      description "List the organization's skipped KSeF sales invoices, oldest first."
      prepare build(sort: [issue_date: :asc, invoice_number: :asc])
    end

    create :record do
      description "Record a KSeF sales invoice the import skipped, or update its reason."

      accept [
        :ksef_number,
        :invoice_number,
        :issue_date,
        :buyer_name,
        :gross_total,
        :currency,
        :reason,
        :ksef_permanent_storage_date
      ]

      upsert? true
      upsert_identity :unique_ksef_number
    end

    destroy :destroy do
      description "Remove a skipped KSeF sales invoice once it is imported."
      primary? true
    end
  end

  policies do
    bypass {SystemActorRole, roles: [:sales_invoice_processor]} do
      authorize_if action([:read, :list, :record, :destroy])
    end

    bypass [
      {SystemActorRole, roles: [:organization_cleanup]},
      action([:read, :list, :destroy])
    ] do
      authorize_if expr(not is_nil(^actor(:org_id)) and organization_id == ^actor(:org_id))
    end

    policy IsSystemActor do
      forbid_if always()
    end

    policy {AtLeastRole, role: :invoicing} do
      authorize_if action([:read, :list])
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :ksef_number, :string, allow_nil?: false, public?: true
    attribute :invoice_number, :string, allow_nil?: false, public?: true
    attribute :issue_date, :date, allow_nil?: false, public?: true
    attribute :buyer_name, :string, public?: true
    attribute :gross_total, :decimal, allow_nil?: false, public?: true
    attribute :currency, :string, allow_nil?: false, public?: true
    attribute :reason, :string, allow_nil?: false, public?: true
    attribute :ksef_permanent_storage_date, :naive_datetime, allow_nil?: false, public?: true

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :organization, Firmowid.Core.Organization do
      allow_nil? false
    end
  end

  identities do
    identity :unique_ksef_number, [:organization_id, :ksef_number]
  end
end
