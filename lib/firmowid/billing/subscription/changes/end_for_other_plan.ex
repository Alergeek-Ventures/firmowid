defmodule Firmowid.Billing.Subscription.Changes.EndForOtherPlan do
  @moduledoc """
  A change of `Organization :update_billing_plan`: once the organization's plan changes, its
  subscription for a different plan ends, whether active or still awaiting a card, so a plan set by
  hand is never charged for the old one and a card saved later does not bring the old plan back.

  The subscription that set the plan already has it, so for `:save_card` this does nothing.
  """

  use Ash.Resource.Change

  alias Firmowid.Billing
  alias Firmowid.Billing.Subscription

  @doc "Ends the organization's not ended subscription for another plan after the plan is saved."
  @spec change(Ash.Changeset.t(), keyword(), Ash.Resource.Change.Context.t()) :: Ash.Changeset.t()
  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, organization ->
      # The plan change is already authorized; ending its subscription is part of it.
      scope = Billing.scope(organization.id)

      with {:ok, subscriptions} <- Subscription.list(scope: scope),
           :ok <- end_other_plans(subscriptions, organization.billing_plan, scope) do
        {:ok, organization}
      end
    end)
  end

  defp end_other_plans(subscriptions, plan, scope) do
    subscriptions
    |> Enum.reject(&(&1.status == :ended or &1.plan == plan))
    |> Enum.reduce_while(:ok, fn subscription, :ok ->
      case Billing.end_subscription(subscription, %{reason: :plan_changed}, scope: scope) do
        {:ok, _subscription} -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end
end
