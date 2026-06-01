defmodule Firmowid.Ash.Blobs.Blob do
  @moduledoc """
  Ash resource for organization-scoped binary objects stored in S3.

  Handles file upload (with image preprocessing), S3 lifecycle, and
  presigned URL generation via the `:url` calculation.
  """
  use Ash.Resource,
    domain: Firmowid.Ash.Blobs,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshOban],
    notifiers: [Ash.Notifier.PubSub]

  alias AshOban.Checks.AshObanInteraction
  alias Firmowid.Ash.Blobs.Changes.DeleteFromS3
  alias Firmowid.Ash.Blobs.Changes.EnqueueCostInvoiceBlobProcessing
  alias Firmowid.Ash.Blobs.Changes.EnqueueEmploymentContractBlobProcessing
  alias Firmowid.Ash.Blobs.Changes.ProcessCostInvoiceBlob
  alias Firmowid.Ash.Blobs.Changes.ProcessEmploymentContractBlob
  alias Firmowid.Ash.Blobs.Changes.UploadToS3
  alias Firmowid.Ash.Blobs.Changes.ValidateProcessingStateTransition
  alias Firmowid.Ash.Checks.ActorBlobIdMatches
  alias Firmowid.Ash.Checks.SystemActorRole
  alias Firmowid.Ash.Resource

  require Resource

  postgres do
    table "blobs"
    repo Firmowid.Repo
  end

  oban do
    use_tenant_from_record? true

    triggers do
      trigger :cleanup_failed_cost_invoice do
        action :cleanup_failed_cost_invoice
        read_action :read_global

        where expr(
                processing_target == :cost_invoice and processing_state == :failed and
                  inserted_at < ago(1, "hour")
              )

        scheduler_cron "0 * * * *"
        queue :cost_invoices

        worker_module_name Firmowid.Ash.Blobs.Blob.Worker.CleanupFailedCostInvoice
        scheduler_module_name Firmowid.Ash.Blobs.Blob.Scheduler.CleanupFailedCostInvoice
      end

      trigger :process_cost_invoice do
        action :process_cost_invoice
        read_action :read_global
        where expr(processing_target == :cost_invoice and processing_state == :pending)
        scheduler_cron "0 * * * *"
        queue :cost_invoices

        worker_module_name Firmowid.Ash.Blobs.Blob.Worker.ProcessCostInvoice
        scheduler_module_name Firmowid.Ash.Blobs.Blob.Scheduler.ProcessCostInvoice
      end

      trigger :process_employment_contract do
        action :process_employment_contract
        read_action :read_global
        where expr(processing_target == :employment_contract and processing_state == :pending)
        scheduler_cron false
        queue :employment_contracts

        worker_module_name Firmowid.Ash.Blobs.Blob.Worker.ProcessEmploymentContract
        scheduler_module_name Firmowid.Ash.Blobs.Blob.Scheduler.ProcessEmploymentContract
      end
    end
  end

  actions do
    defaults [:read]

    read :read_global do
      description "Unscoped read for AshOban schedulers — reads across all organizations."
      multitenancy :allow_global
      pagination keyset?: true
    end

    read :read_pending_cost_invoice_processing do
      description "Scoped scheduler read for pending cost-invoice blob processing."

      pagination do
        required? false
        keyset? true
      end
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
      change Firmowid.Ash.Blobs.Changes.SetProcessingDefaults

      change EnqueueCostInvoiceBlobProcessing do
        where [attribute_equals(:processing_target, :cost_invoice)]
      end

      change EnqueueEmploymentContractBlobProcessing do
        where [attribute_equals(:processing_target, :employment_contract)]
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
    end

    update :mark_processing_succeeded do
      description "Mark a blob as successfully processed and clear processing metadata."
      require_atomic? false
      accept []
      change {ValidateProcessingStateTransition, to: :succeeded}
      change set_attribute(:processing_state, :succeeded)
      change set_attribute(:processing_metadata, %{})
    end

    update :mark_processing_failed do
      description "Mark a blob as failed and store processing error metadata."
      require_atomic? false
      argument :error, :string
      argument :error_code, :string
      argument :error_message, :string
      change {ValidateProcessingStateTransition, to: :failed}
      change set_attribute(:processing_state, :failed)

      change fn changeset, _context ->
        error = Ash.Changeset.get_argument(changeset, :error)
        error_code = Ash.Changeset.get_argument(changeset, :error_code)
        error_message = Ash.Changeset.get_argument(changeset, :error_message)

        metadata = %{
          error: error || "unknown_error",
          error_code: error_code || "processing_failed",
          error_message: error_message || "Nie udało się przetworzyć pliku."
        }

        Ash.Changeset.force_change_attribute(changeset, :processing_metadata, metadata)
      end
    end

    update :process_cost_invoice do
      description "Process a blob as a cost invoice import."
      require_atomic? false
      # Need to update blob processing state in case of processing failures.
      transaction? false

      change ProcessCostInvoiceBlob
    end

    update :process_employment_contract do
      description "Process a blob as an employment contract import."
      require_atomic? false
      # Need to update blob processing state in case of processing failures.
      transaction? false

      change ProcessEmploymentContractBlob
    end

    destroy :destroy do
      description "Delete a blob record and clean up the S3 object."
      primary? true
      require_atomic? false

      change DeleteFromS3
    end

    destroy :cleanup_failed_cost_invoice do
      description "Scheduled trigger — deletes failed cost-invoice blobs older than 1 hour."
      require_atomic? false

      change DeleteFromS3
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :admin) do
      authorize_if always()
    end

    bypass AshObanInteraction do
      authorize_if always()
    end

    # Invoice processors and ksef_session: read + create
    bypass {SystemActorRole,
            roles: [
              :cost_invoice_processor,
              :employment_contract_processor,
              :sales_invoice_processor
            ]} do
      authorize_if action(:read)
    end

    bypass {SystemActorRole, roles: [:cost_invoice_processor, :sales_invoice_processor]} do
      authorize_if action(:create_blob)
    end

    bypass {SystemActorRole, roles: [:cost_invoice_processor, :employment_contract_processor]} do
      authorize_if action([
                     :mark_processing,
                     :mark_processing_pending,
                     :mark_processing_succeeded,
                     :mark_processing_failed,
                     :process_cost_invoice,
                     :process_employment_contract
                   ])
    end

    # Invoice and employment contract processors can destroy blobs only if they own them (e.g., cleanup after processing failures)
    # Both conditions must be true: action is :destroy AND the actor's blob_id matches.
    policy [
      action(:destroy),
      {SystemActorRole, roles: [:cost_invoice_processor, :employment_contract_processor, :sales_invoice_processor]}
    ] do
      authorize_if ActorBlobIdMatches
    end

    policy action(:cleanup_failed_cost_invoice) do
      forbid_if always()
    end

    # ksef_session: create blobs, read all, and destroy only blobs assigned via actor.blob_id
    bypass {SystemActorRole, roles: [:ksef_session]} do
      authorize_if action(:create_blob)
      authorize_if action(:read)
    end

    policy [action(:destroy), {SystemActorRole, roles: [:ksef_session]}] do
      authorize_if ActorBlobIdMatches
    end

    bypass {SystemActorRole, roles: [:cost_invoice_processor, :employment_contract_processor]} do
      authorize_if action(:read_global)
    end

    policy action(:read_global) do
      forbid_if always()
    end

    # Other system actors: no access
    policy Firmowid.Ash.Checks.IsSystemActor do
      forbid_if always()
    end

    # :employee: read + create (for HoursRecord PDF uploads)
    policy [action(:read), actor_attribute_equals(:role, :employee)] do
      authorize_if always()
    end

    policy [action(:create_blob), actor_attribute_equals(:role, :employee)] do
      authorize_if always()
    end

    # :invoicing and :accountant: read only
    policy [action(:read), {Firmowid.Ash.Checks.AtLeastRole, role: :invoicing}] do
      authorize_if always()
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
    publish :process_cost_invoice, ["updated", :_tenant]
    publish :process_employment_contract, ["updated", :_tenant]
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
    belongs_to :organization, Firmowid.Ash.Core.Organization do
      allow_nil? false
    end
  end

  calculations do
    calculate :url, :string, Firmowid.Ash.Blobs.Calculations.BlobUrl
  end

  identities do
    identity :unique_checksum_per_org, [:blob_checksum, :organization_id]
  end
end
