defmodule Firmowid.Blobs.Blob.Policies do
  @moduledoc "Authorization policies for stored files."
  use Spark.Dsl.Fragment, of: Ash.Resource, authorizers: [Ash.Policy.Authorizer]

  alias AshOban.Checks.AshObanInteraction
  alias Firmowid.Checks.ActorBlobIdMatches
  alias Firmowid.Checks.ActorRole
  alias Firmowid.Checks.SystemActorRole

  policies do
    bypass {ActorRole, role: :admin} do
      authorize_if always()
    end

    bypass AshObanInteraction do
      authorize_if always()
    end

    # Invoice processors and ksef_session: read + create
    bypass {SystemActorRole,
            roles: [
              :cost_invoice_processor,
              :document_blob_processor,
              :sales_invoice_processor
            ]} do
      authorize_if action(:read)
    end

    bypass {SystemActorRole, roles: [:cost_invoice_processor, :sales_invoice_processor]} do
      authorize_if action(:create_blob)
    end

    bypass {SystemActorRole, roles: [:cost_invoice_processor, :document_blob_processor]} do
      authorize_if action([
                     :mark_processing,
                     :mark_processing_pending,
                     :mark_processing_succeeded,
                     :mark_processing_failed,
                     :process_document_blob
                   ])
    end

    # Invoice and employment contract processors can destroy blobs only if they own them (e.g., cleanup after processing failures)
    # Both conditions must be true: action is :destroy AND the actor's blob_id matches.
    policy [
      action(:destroy),
      {SystemActorRole, roles: [:cost_invoice_processor, :document_blob_processor, :sales_invoice_processor]}
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

    bypass {SystemActorRole, roles: [:leave_notifier]} do
      authorize_if action(:read)
    end

    policy [action(:destroy), {SystemActorRole, roles: [:ksef_session]}] do
      authorize_if ActorBlobIdMatches
    end

    bypass {SystemActorRole, roles: [:cost_invoice_processor, :document_blob_processor]} do
      authorize_if action(:read_global)
      authorize_if action(:list_processing)
    end

    bypass [{SystemActorRole, roles: [:avatar_cleanup]}, action([:read, :destroy])] do
      authorize_if expr(id == ^actor(:blob_id))
    end

    policy action(:read_global) do
      forbid_if always()
    end

    policy action(:list_processing) do
      forbid_if always()
    end

    # Other system actors: no access
    policy Firmowid.Checks.IsSystemActor do
      forbid_if always()
    end

    # all employees: read and create_blob for hours records, uploading avatar, documents, etc.
    policy action(:list) do
      authorize_if expr(
                     fragment(
                       "?->>'member_id' = ?::text",
                       processing_metadata,
                       ^actor([:member, :id])
                     )
                   )
    end

    policy [action([:read, :create_blob]), {Firmowid.Checks.AtLeastRole, role: :employee}] do
      authorize_if always()
    end
  end
end
