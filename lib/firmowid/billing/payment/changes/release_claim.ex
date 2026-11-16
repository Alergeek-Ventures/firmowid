defmodule Firmowid.Billing.Payment.Changes.ReleaseClaim do
  @moduledoc """
  Gives back the attempt `:charge` claimed when Tpay has no transaction for it a day after
  the claim (see `Firmowid.Billing.Payment.Changes.FetchOutcome`): the charge never reached
  Tpay, so the payment is due again as if the attempt had never been made.

  Only the claim itself is released: the update applies while the payment is still
  `:charging` that attempt and has no Tpay transaction.
  """

  use Ash.Resource.Change

  alias Ash.Resource.Change.Context

  @doc "Returns the payment to its state before the claim."
  @spec change(Ash.Changeset.t(), keyword(), Context.t()) :: Ash.Changeset.t()
  @impl true
  def change(changeset, _opts, _context) do
    %{attempts: attempts} = changeset.data
    previous_status = if attempts > 1, do: :declined, else: :due

    changeset
    |> Ash.Changeset.filter(expr(status == :charging and is_nil(tpay_transaction_id) and attempts == ^attempts))
    |> AshStateMachine.transition_state(previous_status)
    |> Ash.Changeset.force_change_attribute(:attempts, attempts - 1)
  end
end
