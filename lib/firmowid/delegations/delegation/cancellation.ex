defmodule Firmowid.Delegations.Delegation.Cancellation do
  @moduledoc "Cancelling a business trip before its settlement, and deleting it once cancelled."

  use Spark.Dsl.Fragment, of: Ash.Resource

  import AshStateMachine.BuiltinChanges, only: [transition_state: 1]

  alias Firmowid.Delegations.Actions.SendDelegationEmail
  alias Firmowid.Delegations.Signals

  calculations do
    # A settlement returned for corrections is in progress again, but keeps its number.
    calculate :cancellable?,
              :boolean,
              expr(status in [:pending, :in_progress] and is_nil(settlement_sequence)) do
      description "Whether the trip can still be cancelled: its settlement has no number yet."
    end
  end

  actions do
    update :cancel do
      description "Cancel a business trip that has not been settled yet."
      accept []
      # Checks the stored state, so a stale page cannot cancel a trip that has moved on.
      change filter(expr(cancellable?))
      change transition_state(:cancelled)

      emit Signals, :delegation_cancelled,
        fields: [delegation_id: :id],
        values: [cancelled_by_member_id: actor([:member, :id])]
    end

    destroy :destroy do
      description "Delete a cancelled business trip; the database removes its expenses with it."
      primary? true
      change filter(expr(status == :cancelled))
    end

    action :notify_employee_about_cancellation do
      description "Emails the employee that an admin cancelled their delegation."
      argument :signal, Signals.DelegationCancelled, allow_nil?: false
      run {SendDelegationEmail, email: :cancelled_delegation}
    end
  end
end
