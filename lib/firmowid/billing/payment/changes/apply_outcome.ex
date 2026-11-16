defmodule Firmowid.Billing.Payment.Changes.ApplyOutcome do
  @moduledoc """
  Applies a charge's outcome to the payment, read again and locked in the transaction.

  - Paid: a `:charging` or `:declined` payment is paid, whichever attempt Tpay paid, at the time
    Tpay booked it (now when Tpay gives none). The same transaction reported again changes
    nothing; another transaction paying a payment that is already paid, or one that failed or
    was never charged, is an error for a human to refund.
  - Declined, for the current attempt of a `:charging` payment: the next attempt falls on the
    4th or the 8th day of the period, or, after `max_attempts`, the payment fails.
  - Pending, for the current attempt: the payment stays `:charging` with Tpay's transaction,
    which reconciliation asks about later.

  Any other outcome belongs to an attempt that is no longer the current one or repeats one
  already recorded, and changes nothing.
  """

  use Ash.Resource.Change

  alias Ash.Resource.Change.Context

  # Days after the period's first day on which the 1st, 2nd and 3rd attempt fall.
  @attempt_days [0, 3, 7]

  @doc "Sets the payment's status and dates from the outcome, after the payment is locked."
  @spec change(Ash.Changeset.t(), keyword(), Context.t()) :: Ash.Changeset.t()
  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, &apply_outcome/1)
  end

  defp apply_outcome(changeset) do
    payment = changeset.data
    outcome = Ash.Changeset.get_argument(changeset, :outcome)
    transaction_id = Ash.Changeset.get_argument(changeset, :transaction_id)
    current? = Ash.Changeset.get_argument(changeset, :attempt) == payment.attempts

    case {payment.status, outcome} do
      {status, :paid} when status in [:charging, :declined] ->
        changeset
        |> AshStateMachine.transition_state(:paid)
        |> Ash.Changeset.force_change_attributes(%{
          tpay_transaction_id: transaction_id,
          paid_at: Ash.Changeset.get_argument(changeset, :paid_at) || DateTime.utc_now()
        })

      {:paid, :paid} when payment.tpay_transaction_id == transaction_id ->
        changeset

      {status, :paid} ->
        Ash.Changeset.add_error(
          changeset,
          "Tpay transaction #{transaction_id} paid payment #{payment.id}, which is #{status}; refund it"
        )

      {:charging, :declined} when current? ->
        decline(changeset, payment, transaction_id)

      {:charging, :pending} when current? ->
        Ash.Changeset.force_change_attribute(changeset, :tpay_transaction_id, transaction_id)

      _stale_or_repeated ->
        changeset
    end
  end

  defp decline(changeset, %{attempts: attempts, max_attempts: max_attempts}, transaction_id)
       when attempts >= max_attempts do
    changeset
    |> AshStateMachine.transition_state(:failed)
    |> Ash.Changeset.force_change_attribute(:tpay_transaction_id, transaction_id)
  end

  defp decline(changeset, payment, transaction_id) do
    changeset
    |> AshStateMachine.transition_state(:declined)
    |> Ash.Changeset.force_change_attributes(%{
      tpay_transaction_id: transaction_id,
      next_attempt_on: Date.add(payment.period_start, Enum.at(@attempt_days, payment.attempts))
    })
  end
end
