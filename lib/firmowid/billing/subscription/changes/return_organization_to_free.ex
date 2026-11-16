defmodule Firmowid.Billing.Subscription.Changes.ReturnOrganizationToFree do
  @moduledoc """
  Puts the organization back on the Free plan when its subscription ends unpaid, in the same
  transaction, through `Organization :update_billing_plan`, so the plan limits follow.
  """

  use Ash.Resource.Change

  alias Ash.Resource.Change.Context
  alias Firmowid.Core

  @doc "Sets the organization's plan to Free after the subscription ends."
  @spec change(Ash.Changeset.t(), keyword(), Context.t()) :: Ash.Changeset.t()
  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.after_action(changeset, fn _changeset, subscription ->
      opts = Ash.Context.to_opts(context)

      with {:ok, organization} <- Core.get_organization(subscription.organization_id, opts),
           {:ok, _organization} <-
             Core.update_organization_billing_plan(organization, %{billing_plan: :free}, opts) do
        {:ok, subscription}
      end
    end)
  end

  @doc "Adds the same hook to an atomic update."
  @spec atomic(Ash.Changeset.t(), keyword(), Context.t()) :: {:ok, Ash.Changeset.t()}
  @impl true
  def atomic(changeset, opts, context), do: {:ok, change(changeset, opts, context)}
end
