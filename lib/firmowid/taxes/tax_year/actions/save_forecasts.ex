defmodule Firmowid.Taxes.TaxYear.Actions.SaveForecasts do
  @moduledoc """
  Keeps the tax and ZUS payments the forecast expects as expected transactions, so they show in
  the transaction list and raise an inbox alert when they stay unpaid.

  Forecasts the current year, the last one, since the last period of a year is due in January, and
  the one the horizon reaches (see `Firmowid.Taxes.Forecast.Period.horizon/1`), as periods ahead are
  saved too. `Firmowid.Taxes.Forecast.Expectations` decides what to create, update and remove; this
  applies it. The forecast of the running and later periods includes the typical rest or month, so
  the saved amount is that estimate and does not creep up every day; both use the same `today`. It runs for
  the organization of the tenant, as a system actor bound to that organization, from the daily
  scheduled action and from the job that `Changes.EnqueueForecasts` queues when a tax year is saved.
  When the tax year has more than one partner, an owner's payment names the owner, so the rows
  can be told apart.
  """
  use Ash.Resource.Actions.Implementation

  alias Firmowid.Core.Member
  alias Firmowid.Finances
  alias Firmowid.Scope
  alias Firmowid.SystemActor
  alias Firmowid.Taxes
  alias Firmowid.Taxes.Forecast.Expectations
  alias Firmowid.Taxes.Forecast.Period

  @impl true
  def run(input, _opts, context) do
    today = input.arguments.today

    scope = %Scope{
      actor: %SystemActor{org_id: context.tenant, role: :tax_forecaster},
      tenant: context.tenant
    }

    years = Enum.uniq([today.year - 1, today.year, Period.horizon(today).year])
    forecasts = Enum.flat_map(years, &forecasts(&1, today, scope))

    existing =
      Finances.list_expected_transactions!(%{forecast: true}, scope: scope, load: [:is_fulfilled])

    operations = Expectations.plan(forecasts, existing, today)

    Enum.each(operations, &apply_operation(&1, scope))

    {:ok, length(operations)}
  end

  defp apply_operation({:create, attributes}, scope) do
    {forecast_key, attributes} = Map.pop!(attributes, :forecast_key)

    Finances.create_expected_transaction!(attributes,
      scope: scope,
      private_arguments: %{forecast_key: forecast_key}
    )
  end

  defp apply_operation({:update, record, changes}, scope),
    do: Finances.update_expected_transaction_forecast!(record, changes, scope: scope)

  defp apply_operation({:destroy, record}, scope), do: Finances.destroy_expected_transaction!(record, scope: scope)

  defp forecasts(year, today, scope) do
    forecasts = Taxes.forecast_taxes!(year, scope: scope, private_arguments: %{today: today})
    owner_ids = forecasts |> Enum.map(& &1.member_id) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    if match?([_, _ | _], owner_ids) do
      names =
        [query: [filter: [id: [in: owner_ids]]], scope: scope]
        |> Member.list!()
        |> Map.new(&{&1.id, &1.name})

      Enum.map(forecasts, &name_owner(&1, names))
    else
      forecasts
    end
  end

  defp name_owner(%{member_id: member_id} = forecast, names) when is_map_key(names, member_id) do
    case names[member_id] do
      name when name in [nil, ""] -> forecast
      name -> %{forecast | description: "#{forecast.description} (#{name})"}
    end
  end

  defp name_owner(forecast, _names), do: forecast
end
