defmodule Firmowid.SystemActor do
  @moduledoc """
  Actor struct for internal system operations that bypass human authorization.

  System actors represent automated processes or background jobs that need access
  to Ash resources without a human user. Each role is scoped to the minimum
  privileges required for its task.

  ## Roles

  - `:organization_cleanup` — tenant-bound dependent deletion and user detachment.
    Created only after the original actor passes the organization's destroy
    authorization; `org_id` identifies the only organization it may clean up.

  - `:account_cleanup` — deletes OAuth dependents of an authorized account deletion.
    Created only after the original actor passes the user's destroy authorization;
    `user_id` identifies the account, including accounts without an organization.

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
    across invoices and transactions, and lists sessions to split pinned salaries
    between projects.

  - `:analysis_classifier` — keeps analysis entry categories current in the
    background. Reads what the category review reads and stores the categories
    the classifier chose per entry, and caches the register data of counterparties
    that it looks up for them.

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

  - `:hours_record_change_notifier` — reads submitted hours records and emails
    organization admins about correction/cancellation requests.

  - `:employment_contract_notifier` — emails employees about pending employment
    contracts awaiting their signature and notifies org admins when a signed
    contract is submitted. Can read employment contracts and list/read users
    needed for delivery.

  - `:session_auto_stopper` — caps forgotten running timetracker sessions at
    12 hours. Can read sessions and run the auto-stop action.

  - `:anonymous` — unauthenticated share-token access. Can only read the specific
    invoice identified by the share token.

  - `:avatar_cleanup` — cleans up an unreferenced avatar blob after a member or
    organization replaces their avatar. `blob_id` names the old blob: the actor
    can read and destroy only that blob and read only records referencing it.

  - `:actor_member_loader` — loads the authenticated user's active member, which
    decides the user's organization and which policies read the user's role from.
    Can read only the active member of `user_id`, in any organization.

  - `:sign_in_recorder` — records that a session was just issued to `user_id`
    (see `Firmowid.Core.Token.Changes.RecordSignIn`). Can run only that update on
    that account, blocked or not.
  """

  @type role ::
          :organization_cleanup
          | :account_cleanup
          | :cost_invoice_processor
          | :sales_invoice_processor
          | :ksef_session
          | :invoice_matcher
          | :bank_sync
          | :analysis_reader
          | :analysis_classifier
          | :exchange_rate_cache
          | :organization_owner_setup
          | :project_tag_manager
          | :cross_tenant_reader
          | :ksef_digest
          | :billing_snapshotter
          | :document_blob_processor
          | :leave_notifier
          | :hours_record_change_notifier
          | :employment_contract_notifier
          | :session_auto_stopper
          | :anonymous
          | :avatar_cleanup
          | :actor_member_loader
          | :sign_in_recorder

  @enforce_keys [:org_id, :role]
  defstruct [:org_id, :role, :blob_id, :user_id]

  @type t :: %__MODULE__{
          org_id: binary() | nil,
          role: role(),
          blob_id: binary() | nil,
          user_id: binary() | nil
        }
end
