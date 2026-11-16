defmodule Firmowid.Billing.Subscription.Changes.Upgrade do
  @moduledoc """
  Moves an active subscription to the more expensive `plan` argument at once, for the price
  difference of the rest of its paid period (the `:upgrade_price` calculation).

  With nothing to pay, in the organization's free month, the subscription and the organization
  get the plan in the same transaction. Otherwise an `:upgrade` payment with a single attempt
  is opened in the transaction and charged once it commits; one of this month that is still
  due, because its charge never started (Tpay could not be reached), is charged again
  instead; one Tpay refused failed like a declined card. Nothing else charges an upgrade payment. The plan then switches only when
  that payment is paid, as an effect of `Payment :record_outcome`, so a late answer from Tpay
  switches it too and a declined card leaves the plan as it was.

  The charged payment comes back as the record's `:upgrade_payment` metadata, `nil` when
  nothing was charged; the record is read again after the charge, with the plan it has then.
  """

  use Ash.Resource.Change

  alias Ash.Resource.Change.Context
  alias Firmowid.Billing
  alias Firmowid.Billing.Month
  alias Firmowid.Billing.Payment
  alias Firmowid.Billing.PlanCatalog
  alias Firmowid.Billing.Subscription.Changes.SetOrganizationPlan

  require Ash.Query

  @doc "Switches the plan or opens the upgrade payment, and charges that payment after the commit."
  @spec change(Ash.Changeset.t(), keyword(), Context.t()) :: Ash.Changeset.t()
  @impl true
  def change(changeset, _opts, context) do
    plan = Ash.Changeset.get_argument(changeset, :plan)

    if more_expensive?(plan, changeset.data.plan) do
      changeset
      |> Ash.Changeset.before_action(&switch_or_open_payment(&1, plan, context))
      |> Ash.Changeset.after_transaction(&charge/2)
    else
      Ash.Changeset.add_error(
        changeset,
        Ash.Error.Changes.InvalidArgument.exception(
          field: :plan,
          message: "must cost more than the current plan"
        )
      )
    end
  end

  defp more_expensive?(plan, current),
    do: Decimal.gt?(PlanCatalog.plan!(plan).monthly_price_pln, PlanCatalog.plan!(current).monthly_price_pln)

  defp switch_or_open_payment(changeset, plan, context) do
    subscription = changeset.data
    scope = Billing.scope(subscription.organization_id)

    case Ash.load(subscription, [upgrade_price: %{plan: plan}], scope: scope) do
      {:ok, %{upgrade_price: %{gross_amount: gross_amount}}} ->
        if Decimal.eq?(gross_amount, 0) do
          changeset
          |> Ash.Changeset.force_change_attribute(:plan, plan)
          |> SetOrganizationPlan.change([], context)
        else
          Ash.Changeset.after_action(changeset, fn _changeset, subscription ->
            open_payment(subscription, plan, scope)
          end)
        end

      {:error, error} ->
        Ash.Changeset.add_error(changeset, error)
    end
  end

  defp open_payment(subscription, plan, scope) do
    with {:ok, payment} <- due_payment(subscription, plan, scope) do
      {:ok, Ash.Resource.put_metadata(subscription, :upgrade_payment, payment)}
    end
  end

  # One upgrade payment a month (the `:one_per_period` identity); its price holds for the month.
  defp due_payment(subscription, plan, scope) do
    period_start = Month.current()

    query =
      Ash.Query.filter(
        Payment,
        subscription_id == ^subscription.id and kind == :upgrade and plan == ^plan and
          period_start == ^period_start
      )

    case Billing.list_payments(%{status: :due}, query: query, scope: scope) do
      {:ok, [payment]} ->
        {:ok, payment}

      {:ok, []} ->
        Billing.create_payment(
          %{
            subscription_id: subscription.id,
            kind: :upgrade,
            plan: plan,
            billing_period: subscription.billing_period,
            period_start: period_start,
            period_end: subscription.current_period_end,
            max_attempts: 1
          },
          scope: scope
        )

      {:error, error} ->
        {:error, error}
    end
  end

  # After the commit, so the charge's claim commits on its own (see `Payment.Changes.ChargeCard`).
  defp charge(_changeset, {:ok, %{__metadata__: %{upgrade_payment: payment}} = subscription}) do
    scope = Billing.scope(subscription.organization_id)

    with {:ok, payment} <- Billing.charge_payment(payment, scope: scope),
         {:ok, subscription} <- Ash.reload(subscription, scope: scope) do
      {:ok, Ash.Resource.put_metadata(subscription, :upgrade_payment, payment)}
    end
  end

  defp charge(_changeset, {:ok, subscription}), do: {:ok, Ash.Resource.put_metadata(subscription, :upgrade_payment, nil)}

  defp charge(_changeset, error), do: error
end
