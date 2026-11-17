defmodule Firmowid.Billing.Payment.Changes.PricePeriod do
  @moduledoc """
  Prices a payment from the plan catalog: the net price of its plan for its billing period,
  the price with 23% VAT and that rate, as its advance invoice states them.

  An `:upgrade` payment costs what its subscription's move to the payment's plan costs now
  (the subscription's `:upgrade_price`), read before the insert, while the subscription still
  has the plan it moves from.
  """

  use Ash.Resource.Change

  alias Ash.Resource.Change.Context
  alias Firmowid.Billing.PlanCatalog
  alias Firmowid.Billing.Subscription

  @doc "Sets the net and gross amount and the VAT rate."
  @spec change(Ash.Changeset.t(), keyword(), Context.t()) :: Ash.Changeset.t()
  @impl true
  def change(changeset, _opts, context) do
    plan = Ash.Changeset.get_attribute(changeset, :plan)
    billing_period = Ash.Changeset.get_attribute(changeset, :billing_period)

    cond do
      # The missing plan or period fails as a required attribute.
      is_nil(plan) or is_nil(billing_period) ->
        changeset

      Ash.Changeset.get_attribute(changeset, :kind) == :upgrade ->
        Ash.Changeset.before_action(changeset, &price_upgrade(&1, plan, context))

      true ->
        Ash.Changeset.force_change_attributes(changeset, %{
          net_amount: PlanCatalog.net_price_pln(plan, billing_period),
          gross_amount: PlanCatalog.gross_price_pln(plan, billing_period),
          vat_rate: "23"
        })
    end
  end

  defp price_upgrade(changeset, plan, context) do
    subscription_id = Ash.Changeset.get_attribute(changeset, :subscription_id)

    case Ash.get(
           Subscription,
           subscription_id,
           Ash.Context.to_opts(context, load: [upgrade_price: %{plan: plan}])
         ) do
      {:ok, %{upgrade_price: price}} ->
        Ash.Changeset.force_change_attributes(changeset, %{
          net_amount: price.net_amount,
          gross_amount: price.gross_amount,
          vat_rate: "23"
        })

      {:error, error} ->
        Ash.Changeset.add_error(changeset, error)
    end
  end
end
