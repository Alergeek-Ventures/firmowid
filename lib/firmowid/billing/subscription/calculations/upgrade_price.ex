defmodule Firmowid.Billing.Subscription.Calculations.UpgradePrice do
  @moduledoc """
  What moving an active subscription to a more expensive plan costs now: the difference
  between the two plans' net prices for the months left in the paid period, the current month
  included, rounded to the grosz, and that net with 23% VAT. A monthly period has its one month
  left; a yearly one pays the yearly difference for the months left out of twelve. The free month
  owes nothing, and neither does a period that has already ended but is not renewed yet.
  """

  use Ash.Resource.Calculation

  alias Ash.Resource.Calculation.Context
  alias Firmowid.Billing.Month
  alias Firmowid.Billing.PlanCatalog

  @doc "Loads the subscription's plan, period and whether the period is free."
  @spec load(Ash.Query.t(), keyword(), Context.t()) :: [atom()]
  @impl true
  def load(_query, _opts, _context), do: [:plan, :billing_period, :current_period_end, :current_period_free?]

  @doc "Returns `%{net_amount, gross_amount}` of the move to the `plan` argument for each subscription."
  @spec calculate([Ash.Resource.Record.t()], keyword(), Context.t()) :: [map()]
  @impl true
  def calculate(subscriptions, _opts, %{arguments: %{plan: plan}}) do
    Enum.map(subscriptions, &price(&1, plan))
  end

  defp price(%{current_period_free?: true}, _plan),
    do: %{net_amount: Decimal.new("0.00"), gross_amount: Decimal.new("0.00")}

  # The gross is the net with 23% VAT, rounded once, as the advance invoice for it adds the
  # VAT to its net line; so the charged amount always equals the invoice's gross.
  defp price(subscription, plan) do
    %{plan: current, billing_period: billing_period} = subscription

    net_amount =
      plan
      |> PlanCatalog.net_price_pln(billing_period)
      |> Decimal.sub(PlanCatalog.net_price_pln(current, billing_period))
      |> Decimal.mult(months_left(subscription.current_period_end))
      |> Decimal.div(PlanCatalog.months(billing_period))
      |> Decimal.round(2)

    %{net_amount: net_amount, gross_amount: PlanCatalog.with_vat(net_amount)}
  end

  # The months from the current one to the period's last, both included.
  defp months_left(period_end) do
    current = Month.current()
    max((period_end.year - current.year) * 12 + period_end.month - current.month + 1, 0)
  end
end
