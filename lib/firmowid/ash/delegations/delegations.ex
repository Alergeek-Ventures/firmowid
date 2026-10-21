defmodule Firmowid.Ash.Delegations do
  @moduledoc """
  Ash domain for employee business-trip delegations and their settlement.

  All reads and writes use Ash actions with policy-based authorization and
  attribute multitenancy via `organization_id`.
  """

  use Ash.Domain,
    extensions: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Checks.ActorRole
  alias Firmowid.Ash.Delegations.Delegation
  alias Firmowid.Ash.Delegations.DelegationExpense
  alias Firmowid.Ash.Delegations.DelegationExpenseRelatedBlob
  alias Firmowid.Ash.Delegations.DelegationReferenceCounter

  resources do
    resource Delegation do
      define :create_delegation, action: :create
      define :get_delegation, action: :read, get_by: [:id]
      define :get_delegation_by_reference, action: :by_reference, args: [:reference]
      define :list_delegations_for_member, action: :list_for_member, args: [:member_id]
      define :prepare_delegation_command, action: :prepare_command, get_by: [:id]
      define :update_delegation_billing_month, action: :update_billing_month, get_by: [:id]

      define :approve_delegation, action: :approve, get_by: [:id]

      define :complete_delegation, action: :complete, get_by: [:id]
      define :detect_dates, action: :detect_dates
      define :notify_admins_about_delegation, action: :notify_admins, args: [:signal]
      define :notify_employee_about_delegation, action: :notify_employee, args: [:signal]
    end

    resource DelegationExpense do
      define :read_expenses, action: :read
      define :get_expense, action: :read, get_by: [:id]
      define :create_expense, action: :create
      define :update_expense, action: :update
      define :complete_expense, action: :complete
      define :destroy_expense, action: :destroy
      define :add_related_document, action: :add_related_document
      define :remove_related_document, action: :remove_related_document
      define :add_statement_document, action: :add_statement_document
      define :remove_statement_document, action: :remove_statement_document
    end

    resource DelegationExpenseRelatedBlob do
      define :read_related_expense_blobs, action: :read
    end

    resource DelegationReferenceCounter
  end

  policies do
    bypass {ActorRole, role: :admin} do
      authorize_if always()
    end
  end

  authorization do
    authorize :by_default
    require_actor? true
  end
end
