defmodule Firmowid.Ash.Delegations do
  @moduledoc """
  Ash domain for employee business-trip delegations and their settlement.

  All reads and writes use Ash actions with policy-based authorization and
  attribute multitenancy via `organization_id`.
  """

  use Ash.Domain,
    extensions: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Delegations.Delegation
  alias Firmowid.Ash.Delegations.DelegationExpense
  alias Firmowid.Ash.Delegations.DelegationExpenseRelatedBlob

  resources do
    resource Delegation do
      define :create_delegation, action: :create
      define :get_delegation, action: :read, get_by: [:id]
      define :get_delegation_by_reference, action: :by_reference, args: [:reference]
      define :list_delegations_for_user, action: :list_for_user, args: [:user_id]
      define :prepare_delegation_command, action: :prepare_command, get_by: [:id]

      define :approve_delegation, action: :approve, get_by: [:id]

      define :complete_delegation, action: :complete, get_by: [:id]
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
    end

    resource DelegationExpenseRelatedBlob do
      define :read_related_expense_blobs, action: :read
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :admin) do
      authorize_if always()
    end
  end

  authorization do
    authorize :by_default
    require_actor? true
  end
end
