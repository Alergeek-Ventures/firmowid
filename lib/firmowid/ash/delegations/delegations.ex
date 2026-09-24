defmodule Firmowid.Ash.Delegations do
  @moduledoc """
  Ash domain for employee business-trip delegations and their settlement.

  All reads and writes use Ash actions with policy-based authorization and
  attribute multitenancy via `organization_id`.
  """

  use Ash.Domain,
    extensions: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Delegations.Delegation

  resources do
    resource Delegation do
      define :create_delegation, action: :create
      define :get_delegation, action: :read, get_by: [:id]
      define :list_delegations_for_user, action: :list_for_user, args: [:user_id]
      define :approve_delegation, action: :approve, get_by: [:id]
      define :complete_delegation, action: :complete, get_by: [:id]
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
