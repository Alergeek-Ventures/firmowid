defmodule Firmowid.Delegations.Signals do
  @moduledoc """
  Signals emitted by the Delegations domain for other resources to react to.
  """

  use Ash.Signals

  signals do
    signal :delegation_submitted do
      description "An employee submitted a business trip delegation."
      argument :delegation_id, :uuid, allow_nil?: false
      argument :organization_id, :uuid, allow_nil?: false
    end

    signal :delegation_approved do
      description "An admin approved a business trip delegation."
      argument :delegation_id, :uuid, allow_nil?: false
      argument :organization_id, :uuid, allow_nil?: false
    end

    signal :settlement_submitted do
      description "An employee submitted a signed delegation settlement for review."
      argument :delegation_id, :uuid, allow_nil?: false
      argument :organization_id, :uuid, allow_nil?: false
    end

    signal :settlement_reviewed do
      description "An admin accepted a delegation settlement or returned it for corrections."
      argument :delegation_id, :uuid, allow_nil?: false
      argument :organization_id, :uuid, allow_nil?: false
      argument :status, :atom, allow_nil?: false, constraints: [one_of: [:complete, :in_progress]]
      argument :reason, :string
    end
  end
end
