defmodule Firmowid.Ash.SystemActor do
  @moduledoc """
  Actor struct for internal system operations that bypass human authorization.

  System actors represent automated processes or background jobs that need access
  to Ash resources without a human user. Each role is scoped to the minimum
  privileges required for its task.

  ## Roles

  - `:cost_invoice_processor` — processes incoming cost invoices (inbound email
    worker, OCR pipeline). Can read/write cost invoices, blobs, and bank accounts.

  - `:sales_invoice_processor` — processes outgoing sales invoices (KSeF submission
    workers, invoice generation). Can read/write sales invoices and related items.

  - `:ksef_session` — manages KSeF (National e-Invoice System) sessions. Can lock/
    unlock invoices for KSeF submission, update KSeF fields, and read credentials.

  - `:invoice_matcher` — matches bank transactions to invoices. Can read transactions,
    invoices, bank accounts, and connect/disconnect transaction links.

  - `:bank_sync` — synchronizes bank data from GoCardless. Can expire requisitions
    and upsert synced transactions.

  - `:analysis_reader` — performs organization-wide read-only financial analysis
    across invoices and transactions.

  - `:exchange_rate_cache` — persists exchange-rate cache entries for the Money
    exchange-rate backend.

  - `:organization_owner_setup` — bootstrap-only actor used immediately after
    organization creation to assign the new organization to its owner and promote
    that specific user to `:admin`.

  - `:project_tag_manager` — manages analysis tag definitions created as an
    implementation detail of timetracker projects.

  - `:cross_tenant_reader` — reads data across organization boundaries. Used by the
    KSeF fetch dispatcher to enumerate all organizations and queue per-org work.

  - `:ksef_digest` — builds and delivers scheduled KSeF cost-invoice digests.
    Can read invoice and admin-user data required for digest delivery.

  - `:billing_snapshotter` — creates monthly billing snapshots from factual
    organization usage data. Can read billing-related records and persist
    snapshot rows.

  - `:document_blob_processor` — processes document blobs for various use cases.
    Can read/write blobs and read related records as needed for blob processing.

  - `:leave_notifier` — emails org admins about new leave/absence requests.
    Can read leave requests and list/read users needed for delivery.

  - `:employment_contract_notifier` — emails employees about pending employment
    contracts awaiting their signature. Can read employment contracts and users
    needed for delivery.

  - `:anonymous` — unauthenticated share-token access. Can only read the specific
    invoice identified by the share token.

  - `:avatar_cleanup` — cleans up unreferenced avatar blobs after a user or
    organization updates their avatar. Can read/write blobs and read related
    records as needed for blob cleanup.
  """

  @type role ::
          :cost_invoice_processor
          | :sales_invoice_processor
          | :ksef_session
          | :invoice_matcher
          | :bank_sync
          | :analysis_reader
          | :exchange_rate_cache
          | :organization_owner_setup
          | :project_tag_manager
          | :cross_tenant_reader
          | :ksef_digest
          | :billing_snapshotter
          | :document_blob_processor
          | :leave_notifier
          | :employment_contract_notifier
          | :anonymous
          | :avatar_cleanup

  @enforce_keys [:org_id, :role]
  defstruct [:org_id, :role, :blob_id, :user_id]

  @type t :: %__MODULE__{
          org_id: binary() | nil,
          role: role(),
          blob_id: binary() | nil,
          user_id: binary() | nil
        }
end
