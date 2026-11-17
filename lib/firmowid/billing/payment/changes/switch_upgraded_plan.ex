defmodule Firmowid.Billing.Payment.Changes.SwitchUpgradedPlan do
  @moduledoc """
  Moves the subscription and its organization to the plan of an upgrade payment once it is
  paid, in the same transaction, whenever the outcome arrives: from the charge, the
  reconciliation or Tpay's notification. A subscription that ended meanwhile stays as it ended.
  """

  use Ash.Resource.Change

  alias Ash.Resource.Change.Context
  alias Firmowid.Billing

  @doc "Switches the subscription's plan after the payment is saved as paid."
  @spec change(Ash.Changeset.t(), keyword(), Context.t()) :: Ash.Changeset.t()
  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn changeset, payment ->
      if payment.status == :paid and changeset.data.status != :paid do
        switch_plan(payment)
      else
        {:ok, payment}
      end
    end)
  end

  defp switch_plan(payment) do
    scope = Billing.scope(payment.organization_id)

    with {:ok, %{subscription: subscription}} <- Ash.load(payment, :subscription, scope: scope),
         {:ok, _subscription} <- switch_active(subscription, payment.plan, scope) do
      {:ok, payment}
    end
  end

  defp switch_active(%{status: :active} = subscription, plan, scope),
    do: Billing.switch_subscription_plan(subscription, %{plan: plan}, scope: scope)

  defp switch_active(subscription, _plan, _scope), do: {:ok, subscription}
end
