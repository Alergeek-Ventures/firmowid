defmodule Firmowid.Billing.Subscription.Changes.SetOrganizationPlan do
  @moduledoc """
  Gives the organization the plan of its subscription, just activated or moved to another plan,
  in the same transaction, through `Organization :update_billing_plan`, so the plan limits follow
  the new plan.

  The plan is set as the `:billing` system actor: the subscription's own action is already
  authorized, and an admin who upgrades may not set a plan by hand.
  """

  use Ash.Resource.Change

  alias Ash.Resource.Change.Context
  alias Firmowid.Billing
  alias Firmowid.Core

  @doc "Sets the organization's plan after the subscription is saved."
  @spec change(Ash.Changeset.t(), keyword(), Context.t()) :: Ash.Changeset.t()
  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, subscription ->
      set_plan(subscription, scope: Billing.scope(subscription.organization_id))
    end)
  end

  @doc "Adds the same hook to an atomic update."
  @spec atomic(Ash.Changeset.t(), keyword(), Context.t()) ::
          {:ok, Ash.Changeset.t()}
  @impl true
  def atomic(changeset, opts, context), do: {:ok, change(changeset, opts, context)}

  defp set_plan(subscription, opts) do
    with {:ok, organization} <- Core.get_organization(subscription.organization_id, opts),
         {:ok, _organization} <-
           Core.update_organization_billing_plan(
             organization,
             %{billing_plan: subscription.plan},
             opts
           ) do
      {:ok, subscription}
    end
  end
end
