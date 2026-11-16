defmodule Firmowid.Billing.Payment.Changes.FetchOutcome do
  @moduledoc """
  The variant of `:record_outcome` that asks Tpay: called without an outcome, it reads the
  transaction from Tpay before the transaction starts and records what Tpay states, never
  what the caller says about it.

  The transaction is the `transaction_id` argument (a Tpay notification names it), else the
  payment's own, else it is looked up among Tpay's transactions by the attempt it carries,
  when the charge's answer never arrived. It counts only when it carries this payment's
  attempt (the `attempt` argument, else the current one) and the payment's amount. A
  transaction Tpay does not know of ours, or one that does not match, fails the action with
  an invalid `transaction_id`.

  An attempt Tpay has no transaction for a day after its claim was never charged: it is
  released (`:release`) and nothing is recorded. Earlier, Tpay's list may still lag, so
  nothing is decided and the error is reported.

  A charge still pending a day after its claim will not be paid: Tpay keeps a charge of a
  card token it cannot use pending with no attempt. It is recorded as declined, which cancels
  it at Tpay.
  """

  use Ash.Resource.Change

  alias Ash.Error.Changes.InvalidArgument
  alias Ash.Resource.Change.Context
  alias Firmowid.Billing
  alias Firmowid.Billing.Tpay.Client

  @doc "Fetches the attempt's outcome from Tpay when none is given."
  @spec change(Ash.Changeset.t(), keyword(), Context.t()) :: Ash.Changeset.t()
  @impl true
  def change(changeset, _opts, _context) do
    if Ash.Changeset.get_argument(changeset, :outcome) do
      changeset
    else
      Ash.Changeset.before_transaction(changeset, &fetch_outcome/1)
    end
  end

  defp fetch_outcome(changeset) do
    payment = changeset.data
    attempt = Ash.Changeset.get_argument(changeset, :attempt) || payment.attempts

    transaction_id =
      Ash.Changeset.get_argument(changeset, :transaction_id) || payment.tpay_transaction_id

    case transaction(payment, transaction_id, attempt) do
      {:ok, nil} when is_nil(transaction_id) ->
        release_if_never_charged(changeset, payment)

      {:ok, transaction} ->
        if charges_attempt?(transaction, payment, attempt) do
          # Set in a hook, after the action validated its input.
          Ash.Changeset.force_set_arguments(changeset, %{
            outcome: settle_pending(transaction.outcome, payment),
            transaction_id: transaction.transaction_id,
            attempt: attempt,
            paid_at: transaction.paid_at
          })
        else
          Ash.Changeset.add_error(
            changeset,
            InvalidArgument.exception(
              field: :transaction_id,
              message: "is not a Tpay transaction of this payment's attempt"
            )
          )
        end

      {:error, error} ->
        Ash.Changeset.add_error(changeset, error)
    end
  end

  defp transaction(payment, nil, attempt) do
    # The attempt was claimed at the latest update; a day earlier leaves room for clock skew.
    Client.find_transaction(payment.id, attempt, DateTime.shift(payment.updated_at, day: -1))
  end

  defp transaction(_payment, transaction_id, _attempt), do: Client.transaction_outcome(transaction_id)

  # `nil` is a transaction Tpay does not know of ours.
  defp charges_attempt?(nil, _payment, _attempt), do: false

  defp charges_attempt?(transaction, payment, attempt) do
    transaction.payment_id == payment.id and transaction.attempt == attempt and
      Decimal.eq?(transaction.amount, payment.gross_amount)
  end

  defp settle_pending(:pending, payment) do
    if claimed_a_day_ago?(payment), do: :declined, else: :pending
  end

  defp settle_pending(outcome, _payment), do: outcome

  defp release_if_never_charged(changeset, payment) do
    if claimed_a_day_ago?(payment) do
      case Billing.release_payment(payment, scope: Billing.scope(payment.organization_id)) do
        {:ok, _released} -> changeset
        {:error, error} -> Ash.Changeset.add_error(changeset, error)
      end
    else
      Ash.Changeset.add_error(
        changeset,
        "Tpay has no transaction for attempt #{payment.attempts} of payment #{payment.id} yet; " <>
          "it is released if none appears a day after its claim"
      )
    end
  end

  defp claimed_a_day_ago?(payment), do: DateTime.before?(payment.updated_at, DateTime.shift(DateTime.utc_now(), day: -1))
end
