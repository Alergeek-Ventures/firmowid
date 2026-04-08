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

  - `:anonymous` — unauthenticated share-token access. Can only read the specific
    invoice identified by the share token.
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
          | :anonymous

  @enforce_keys [:org_id, :role]
  defstruct [:org_id, :role, :blob_id, :user_id]

  @type t :: %__MODULE__{
          org_id: binary() | nil,
          role: role(),
          blob_id: binary() | nil,
          user_id: binary() | nil
        }
end
