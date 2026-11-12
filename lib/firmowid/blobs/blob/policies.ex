defmodule Firmowid.Blobs.Blob.Policies do
  @moduledoc "Authorization policies for stored files."
  use Spark.Dsl.Fragment, of: Ash.Resource, authorizers: [Ash.Policy.Authorizer]

  alias AshOban.Checks.AshObanInteraction
  alias Firmowid.Blobs.Checks.CanReadHolder
  alias Firmowid.Checks.ActorRole
  alias Firmowid.Checks.AtLeastRole
  alias Firmowid.Checks.SystemActorRole
  alias Firmowid.Delegations.Delegation
  alias Firmowid.Delegations.DelegationExpense
  alias Firmowid.Delegations.DelegationExpenseRelatedBlob
  alias Firmowid.Invoicing.CostInvoice
  alias Firmowid.Payroll.MemberPayrollInput
  alias Firmowid.Payroll.MemberTaxDeclaration
  alias Firmowid.Payroll.UserEmploymentContract
  alias Firmowid.Timetracker.HoursRecord
  alias Firmowid.Timetracker.LeaveRequest

  policies do
    bypass {ActorRole, role: :admin} do
      authorize_if always()
    end

    bypass AshObanInteraction do
      authorize_if always()
    end

    bypass {SystemActorRole,
            roles: [
              :cost_invoice_processor,
              :document_blob_processor,
              :sales_invoice_processor,
              :ksef_session,
              :leave_notifier
            ]} do
      authorize_if action(:read)
    end

    bypass {SystemActorRole, roles: [:cost_invoice_processor, :sales_invoice_processor, :ksef_session]} do
      authorize_if action(:create_blob)
    end

    bypass {SystemActorRole, roles: [:cost_invoice_processor, :document_blob_processor]} do
      authorize_if action([
                     :read_global,
                     :list_processing,
                     :mark_processing,
                     :mark_processing_pending,
                     :mark_processing_succeeded,
                     :mark_processing_failed,
                     :process_document_blob
                   ])
    end

    bypass [{SystemActorRole, roles: [:avatar_cleanup]}, action([:read, :destroy])] do
      authorize_if expr(id == ^actor(:blob_id))
    end

    policy action([:read_global, :list_processing]) do
      forbid_if always()
    end

    # Other system actors: no access
    policy Firmowid.Checks.IsSystemActor do
      forbid_if always()
    end

    policy action(:list) do
      authorize_if expr(
                     fragment(
                       "?->>'member_id' = ?::text",
                       processing_metadata,
                       ^actor([:member, :id])
                     )
                   )
    end

    policy [action(:create_blob), {AtLeastRole, role: :employee}] do
      authorize_if always()
    end

    policy [action(:read), {AtLeastRole, role: :employee}] do
      description "A member reads a file held by a record they may read, a picture, their own document or a new upload."

      # Loaded through its owner: the owner record has already been authorized.
      authorize_if accessing_from(CostInvoice, :blob)
      authorize_if accessing_from(UserEmploymentContract, :blob)
      authorize_if accessing_from(MemberTaxDeclaration, :source_blob)
      authorize_if accessing_from(MemberPayrollInput, :source_blob)
      authorize_if accessing_from(HoursRecord, :blob)
      authorize_if accessing_from(LeaveRequest, :blob)
      authorize_if accessing_from(Delegation, :signed_command_blob)
      authorize_if accessing_from(Delegation, :signed_settlement_blob)
      authorize_if accessing_from(DelegationExpense, :blob)
      authorize_if accessing_from(DelegationExpense, :statement_blob)
      authorize_if accessing_from(DelegationExpense, :related_blobs)
      authorize_if accessing_from(DelegationExpenseRelatedBlob, :blob)

      # Read directly, e.g. by id or by checksum.
      authorize_if {CanReadHolder,
                    relationships: [
                      :cost_invoices,
                      :employment_contracts,
                      :tax_declarations,
                      :payroll_inputs,
                      :hours_records,
                      :leave_requests,
                      :signed_command_delegations,
                      :signed_settlement_delegations,
                      :delegation_expenses,
                      :statement_delegation_expenses,
                      :delegation_expense_links
                    ]}

      # Pictures are shown to the whole organization.
      authorize_if expr(exists(avatar_members, true) or exists(avatar_organizations, true))

      # An employee document, before and after it is turned into records.
      authorize_if expr(
                     fragment(
                       "?->>'member_id' = ?::text",
                       processing_metadata,
                       ^actor([:member, :id])
                     )
                   )

      # A cost invoice file still being processed, for the roles that read cost invoices.
      authorize_if expr(
                     processing_target == :cost_invoice and
                       ^actor([:member, :role]) in [:invoicing, :accountant]
                   )

      # A file just uploaded, before the record that holds it is saved. Every flow
      # attaches the file in the request that uploads it; the limit keeps a file
      # that was later detached from its record from becoming readable by everyone.
      authorize_if expr(
                     processing_target == :none and
                       inserted_at > ago(1, :hour) and
                       not exists(avatar_members, true) and
                       not exists(avatar_organizations, true) and
                       not exists(cost_invoices, true) and
                       not exists(employment_contracts, true) and
                       not exists(tax_declarations, true) and
                       not exists(payroll_inputs, true) and
                       not exists(hours_records, true) and
                       not exists(leave_requests, true) and
                       not exists(signed_command_delegations, true) and
                       not exists(signed_settlement_delegations, true) and
                       not exists(delegation_expenses, true) and
                       not exists(statement_delegation_expenses, true) and
                       not exists(delegation_expense_links, true)
                   )
    end
  end
end
