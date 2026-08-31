defmodule Firmowid.Ash.Delegations do
  @moduledoc """
  Ash domain for employee business-trip delegations and their settlement.

  All reads and writes use Ash actions with policy-based authorization and
  attribute multitenancy via `organization_id`.
  """

  use Ash.Domain,
    extensions: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Delegations.Delegation
  alias Firmowid.Ash.Delegations.DelegationExpenseAccommodation
  alias Firmowid.Ash.Delegations.DelegationExpenseOther
  alias Firmowid.Ash.Delegations.DelegationExpenseTransport
  alias Firmowid.Ash.Delegations.DelegationTrip

  resources do
    resource Delegation do
      define :create_delegation, action: :create
      define :get_delegation, action: :read, get_by: [:id]
      define :list_delegations_for_user, action: :list_for_user, args: [:user_id]
      define :approve_delegation, action: :approve, get_by: [:id]
      define :complete_delegation, action: :complete, get_by: [:id]
    end

    resource DelegationExpenseTransport do
      define :read_transport_expenses, action: :read
      define :get_transport_expense, action: :read, get_by: [:id]
      define :create_transport_expense, action: :create
      define :update_transport_expense, action: :update
      define :destroy_transport_expense, action: :destroy
    end

    resource DelegationExpenseAccommodation do
      define :read_accommodation_expenses, action: :read
      define :get_accommodation_expense, action: :read, get_by: [:id]
      define :create_accommodation_expense, action: :create
      define :update_accommodation_expense, action: :update
      define :destroy_accommodation_expense, action: :destroy
    end

    resource DelegationExpenseOther do
      define :read_other_expenses, action: :read
      define :get_other_expense, action: :read, get_by: [:id]
      define :create_other_expense, action: :create
      define :update_other_expense, action: :update
      define :destroy_other_expense, action: :destroy
    end

    resource DelegationTrip do
      define :read_delegation_trips, action: :read
      define :get_delegation_trip, action: :read, get_by: [:id]
      define :create_delegation_trip, action: :create
      define :update_delegation_trip, action: :update
      define :destroy_delegation_trip, action: :destroy
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
