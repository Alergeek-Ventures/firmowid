defmodule Firmowid.Billing.Subscription.Changes.OpenPeriod do
  @moduledoc """
  Opens the subscription's next paid-for period, and the payment for it unless it is free.

  The first period (`:save_card`, no charge date yet) is the current Warsaw month: free while
  the organization has its free month (`free_month_available?`), otherwise a full month or
  twelve paid at once. A renewal (`:renew`) opens the period starting on `next_charge_on`, or
  the current one when that has already passed, so months in between are not billed. The next
  charge falls on the day after the period.

  Options:

  - `:attempts` — how many charges the payment tries before it fails and the subscription ends.
  - `:charge_at_once?` — queue the charge with the commit instead of leaving it to the daily run.
  """

  use Ash.Resource.Change

  alias Ash.Resource.Change.Context
  alias Firmowid.Billing
  alias Firmowid.Billing.Month
  alias Firmowid.Billing.PlanCatalog
  alias Firmowid.Core
  alias Firmowid.LocalDate

  @doc "Sets the period and the next charge date, then opens the period's payment."
  @spec change(Ash.Changeset.t(), keyword(), Context.t()) :: Ash.Changeset.t()
  @impl true
  def change(changeset, opts, _context) do
    Ash.Changeset.before_action(changeset, &open_period(&1, opts))
  end

  defp open_period(changeset, opts) do
    subscription = changeset.data
    scope = Billing.scope(subscription.organization_id)

    case Core.get_organization(subscription.organization_id,
           scope: scope,
           load: [:free_month_available?]
         ) do
      {:ok, %{free_month_available?: true}} -> open_free_month(changeset)
      {:ok, _organization} -> open_paid_period(changeset, subscription, opts, scope)
      {:error, error} -> Ash.Changeset.add_error(changeset, error)
    end
  end

  defp open_free_month(changeset) do
    month = Month.current()

    Ash.Changeset.force_change_attributes(changeset, %{
      current_period_start: month,
      current_period_end: Date.end_of_month(month),
      next_charge_on: Date.shift(month, month: 1)
    })
  end

  defp open_paid_period(changeset, subscription, opts, scope) do
    months = PlanCatalog.months(subscription.billing_period)

    period_start =
      current_start(subscription.next_charge_on || Month.current(), months, LocalDate.today())

    next_start = Date.shift(period_start, month: months)
    period_end = Date.add(next_start, -1)

    changeset
    |> Ash.Changeset.force_change_attributes(%{
      current_period_start: period_start,
      current_period_end: period_end,
      next_charge_on: next_start
    })
    |> Ash.Changeset.after_action(fn _changeset, subscription ->
      open_payment(subscription, opts, scope)
    end)
  end

  defp open_payment(subscription, opts, scope) do
    with {:ok, payment} <-
           Billing.create_payment(
             %{
               subscription_id: subscription.id,
               kind: :period,
               plan: subscription.plan,
               billing_period: subscription.billing_period,
               period_start: subscription.current_period_start,
               period_end: subscription.current_period_end,
               max_attempts: Keyword.fetch!(opts, :attempts)
             },
             scope: scope
           ) do
      # The job is inserted in this transaction, so it runs only once the payment is committed.
      if opts[:charge_at_once?], do: AshOban.run_trigger(payment, :charge)
      {:ok, subscription}
    end
  end

  # The latest period start on or before today, stepping from `start` by whole periods.
  defp current_start(start, months, today) do
    next_start = Date.shift(start, month: months)

    if Date.after?(next_start, today),
      do: start,
      else: current_start(next_start, months, today)
  end
end
