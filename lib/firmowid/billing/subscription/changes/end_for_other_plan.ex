defmodule Firmowid.Billing.Subscription.Changes.EndForOtherPlan do
  @moduledoc """
  A change of the organization's shared `:plan_change` pipeline: once the organization's plan
  changes, every subscription that does not carry the new plan ends, so a plan set by hand is never
  charged for the old one and a card saved later does not bring the old plan back. Only an active
  subscription for the new plan stays. A subscription still awaiting its card always ends, so
  a late card notification finds nothing to activate.

  The subscription that set the plan is already active with it, so for `:save_card` this does
  nothing.
  """

  use Ash.Resource.Change

  alias Firmowid.Billing
  alias Firmowid.Billing.Subscription

  @doc "Ends the organization's not ended subscriptions other than the active one for the new plan."
  @spec change(Ash.Changeset.t(), keyword(), Ash.Resource.Change.Context.t()) :: Ash.Changeset.t()
  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, organization ->
      # The plan change is already authorized; ending its subscription is part of it.
      scope = Billing.scope(organization.id)

      with {:ok, subscriptions} <- Subscription.list(scope: scope),
           :ok <- end_superseded(subscriptions, organization.billing_plan, scope) do
        {:ok, organization}
      end
    end)
  end

  defp end_superseded(subscriptions, plan, scope) do
    subscriptions
    |> Enum.reject(&(&1.status == :ended or (&1.status == :active and &1.plan == plan)))
    |> Enum.reduce_while(:ok, fn subscription, :ok ->
      case Billing.end_subscription(subscription, %{reason: :plan_changed}, scope: scope) do
        {:ok, _subscription} -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end
end
