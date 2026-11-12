defmodule Firmowid.Blobs.Blob do
  @moduledoc """
  Ash resource for organization-scoped binary objects stored in S3.

  Handles file upload (with image preprocessing), S3 lifecycle, and
  presigned URL generation via the `:url` calculation.
  """
  use Ash.Resource,
    domain: Firmowid.Blobs,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshOban],
    notifiers: [Ash.Notifier.PubSub],
    fragments: [Firmowid.Blobs.Blob.Persistence, Firmowid.Blobs.Blob.Policies]

  use Gettext, backend: Firmowid.Gettext

  alias Firmowid.Blobs.Changes.DeleteFromS3
  alias Firmowid.Blobs.Changes.ProcessDocumentBlob
  alias Firmowid.Blobs.Changes.UploadToS3
  alias Firmowid.Blobs.Changes.ValidateProcessingStateTransition
  alias Firmowid.Core.Member
  alias Firmowid.Core.Organization
  alias Firmowid.Delegations.Delegation
  alias Firmowid.Delegations.DelegationExpense
  alias Firmowid.Delegations.DelegationExpenseRelatedBlob
  alias Firmowid.Invoicing.CostInvoice
  alias Firmowid.Payroll.MemberPayrollInput
  alias Firmowid.Payroll.MemberTaxDeclaration
  alias Firmowid.Payroll.UserEmploymentContract
  alias Firmowid.Resource
  alias Firmowid.Timetracker.HoursRecord
  alias Firmowid.Timetracker.LeaveRequest

  require Resource

  oban do
    use_tenant_from_record? true

    triggers do
      trigger :cleanup_failed_document_blobs do
        action :cleanup_failed_document_blob
        read_action :read_global

        where expr(
                processing_target != :none and processing_state == :failed and
                  inserted_at < ago(1, "hour")
              )

        scheduler_cron "0 * * * *"
        queue :document_blobs

        worker_module_name Firmowid.Blobs.Blob.Worker.CleanupFailedDocumentBlob
        scheduler_module_name Firmowid.Blobs.Blob.Scheduler.CleanupFailedDocumentBlob
      end

      trigger :process_document_blobs do
        action :process_document_blob
        read_action :read_global
        where expr(processing_target != :none and processing_state == :pending)
        scheduler_cron "0 * * * *"
        queue :document_blobs

        worker_module_name Firmowid.Blobs.Blob.Worker.ProcessDocumentBlob
        scheduler_module_name Firmowid.Blobs.Blob.Scheduler.ProcessDocumentBlob
      end
    end
  end

  code_interface do
    define :list, action: :list
    define :read_global, action: :read_global
    define :list_processing, action: :list_processing, args: [:processing_target]
    define :mark_processing, action: :mark_processing
    define :mark_processing_pending, action: :mark_processing_pending
    define :mark_processing_succeeded, action: :mark_processing_succeeded

    define :mark_processing_failed,
      action: :mark_processing_failed,
      args: [:error, :error_code, :error_message, :cost_invoice_id]

    define :process_document_blob, action: :process_document_blob
    define :cleanup_failed_document_blob, action: :cleanup_failed_document_blob
  end

  actions do
    defaults [:read]

    read :list do
      description "List stored files, optionally by processing target and employee."

      argument :processing_target, :atom, constraints: [one_of: [:none, :cost_invoice, :employment_contract]]

      argument :member_id, :uuid

      prepare build(filter: expr(processing_target == ^arg(:processing_target))) do
        where present(:processing_target)
      end

      prepare build(filter: expr(fragment("?->>'member_id' = ?::text", processing_metadata, ^arg(:member_id)))) do
        where present(:member_id)
      end

      prepare build(sort: [inserted_at: :desc])
    end

    read :read_global do
      description "Unscoped read for AshOban schedulers — reads across all organizations."
      multitenancy :allow_global
      pagination keyset?: true
    end

    read :list_processing do
      description "Returns blobs with processing state pending or processing for a given target."

      argument :processing_target, :atom,
        constraints: [one_of: [:cost_invoice, :employment_contract]],
        allow_nil?: false

      prepare build(
                filter:
                  expr(
                    processing_target == ^arg(:processing_target) and
                      (processing_state == :pending or processing_state == :processing)
                  )
              )
    end

    create :create_blob do
      description "Upload a file to S3 and create a blob record."

      argument :upload_path, :string, allow_nil?: false
      argument :content_type, :string, allow_nil?: false
      argument :original_filename, :string, allow_nil?: false

      argument :processing_target, :atom,
        constraints: [one_of: [:none, :cost_invoice, :employment_contract]],
        default: :none

      argument :processing_metadata, :map, default: %{}

      change UploadToS3
      change Firmowid.Blobs.Changes.SetProcessingDefaults

      change run_oban_trigger(:process_document_blobs) do
        where [attribute_does_not_equal(:processing_target, :none)]
      end
    end

    update :mark_processing do
      description "Mark a blob as currently being processed."
      primary? true
      require_atomic? false
      accept []
      change {ValidateProcessingStateTransition, to: :processing}
      change set_attribute(:processing_state, :processing)
    end

    update :mark_processing_pending do
      description "Mark a blob as pending processing."
      require_atomic? false
      accept []
      change {ValidateProcessingStateTransition, to: :pending}
      change set_attribute(:processing_state, :pending)
      change run_oban_trigger(:process_document_blobs)
    end

    update :mark_processing_succeeded do
      description "Mark a blob as processed, retaining employee document ownership."
      require_atomic? false
      accept []
      change {ValidateProcessingStateTransition, to: :succeeded}
      change set_attribute(:processing_state, :succeeded)

      change fn changeset, _context ->
        metadata =
          if changeset.data.processing_target == :employment_contract do
            Map.take(changeset.data.processing_metadata, ["member_id"])
          else
            %{}
          end

        Ash.Changeset.force_change_attribute(changeset, :processing_metadata, metadata)
      end
    end

    update :mark_processing_failed do
      description "Mark a blob as failed and store processing error metadata."
      require_atomic? false
      argument :error, :string
      argument :error_code, :string
      argument :error_message, :string
      argument :cost_invoice_id, :uuid_v7
      change {ValidateProcessingStateTransition, to: :failed}
      change set_attribute(:processing_state, :failed)

      change fn changeset, _context ->
        error = Ash.Changeset.get_argument(changeset, :error)
        error_code = Ash.Changeset.get_argument(changeset, :error_code)
        error_message = Ash.Changeset.get_argument(changeset, :error_message)
        cost_invoice_id = Ash.Changeset.get_argument(changeset, :cost_invoice_id)

        metadata = %{
          error: error || "unknown_error",
          error_code: error_code || "processing_failed",
          error_message: error_message || gettext_noop("Could not process the file.")
        }

        metadata =
          if cost_invoice_id,
            do: Map.put(metadata, :cost_invoice_id, cost_invoice_id),
            else: metadata

        Ash.Changeset.force_change_attribute(changeset, :processing_metadata, metadata)
      end
    end

    update :process_document_blob do
      description "Process a blob."
      require_atomic? false
      # Need to update blob processing state in case of processing failures.
      transaction? false

      change ProcessDocumentBlob
    end

    destroy :destroy do
      description "Delete a blob record and clean up the S3 object."
      primary? true
      require_atomic? false

      change DeleteFromS3
    end

    destroy :cleanup_failed_document_blob do
      description "Scheduled trigger — deletes failed cost-invoice blobs older than 1 hour."
      require_atomic? false

      change DeleteFromS3
    end
  end

  pub_sub do
    module FirmowidWeb.Core.Endpoint
    prefix "blob"

    publish :create_blob, ["created", :_tenant]
    publish :destroy, ["destroyed", :_tenant]
    publish :mark_processing, ["updated", :_tenant]
    publish :mark_processing_pending, ["updated", :_tenant]
    publish :mark_processing_succeeded, ["updated", :_tenant]
    publish :mark_processing_failed, ["updated", :_tenant]
    publish :process_document_blob, ["updated", :_tenant]
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :blob_path, :string, public?: true, allow_nil?: false
    attribute :blob_checksum, :string, public?: true, allow_nil?: false
    attribute :original_filename, :string, public?: true, allow_nil?: false

    attribute :processing_target, :atom,
      public?: true,
      allow_nil?: false,
      default: :none,
      constraints: [one_of: [:none, :cost_invoice, :employment_contract]]

    attribute :processing_state, :atom,
      public?: true,
      allow_nil?: false,
      default: :succeeded,
      constraints: [one_of: [:pending, :processing, :succeeded, :failed]]

    attribute :processing_metadata, :map, public?: true, allow_nil?: false, default: %{}

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :organization, Organization do
      allow_nil? false
    end

    # The records that hold this file; its read policy follows theirs.
    has_many :avatar_members, Member, destination_attribute: :avatar_blob_id
    has_many :avatar_organizations, Organization, destination_attribute: :avatar_blob_id
    has_many :cost_invoices, CostInvoice
    has_many :employment_contracts, UserEmploymentContract
    has_many :tax_declarations, MemberTaxDeclaration, destination_attribute: :source_blob_id
    has_many :payroll_inputs, MemberPayrollInput, destination_attribute: :source_blob_id
    has_many :hours_records, HoursRecord
    has_many :leave_requests, LeaveRequest

    has_many :signed_command_delegations, Delegation, destination_attribute: :signed_command_blob_id

    has_many :signed_settlement_delegations, Delegation, destination_attribute: :signed_settlement_blob_id

    has_many :delegation_expenses, DelegationExpense

    has_many :statement_delegation_expenses, DelegationExpense, destination_attribute: :statement_blob_id

    has_many :delegation_expense_links, DelegationExpenseRelatedBlob
  end

  calculations do
    calculate :url, :string, Firmowid.Blobs.Calculations.BlobUrl
  end

  identities do
    identity :unique_checksum_per_org, [:blob_checksum, :organization_id]
  end
end
