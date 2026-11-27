defmodule Firmowid.Taxes.Forecast.Expectations do
  @moduledoc """
  Decides how the expected transactions kept by the tax forecast change: one per forecast payment
  that is due, identified by its forecast key (`vat:2026-11`, `cit:2026-Q4`, `zus:2026-11:<member id>`).

  Pure: it takes the forecasts, the expectations that have a forecast key (with `is_fulfilled`
  loaded) and today's date, and returns the operations that bring the expectations in step with
  the forecasts. `Firmowid.Taxes.TaxYear.Actions.SaveForecasts` applies them.

    * A forecast with an amount whose period starts within the horizon of
      `Firmowid.Taxes.Forecast.Period.horizon/1` (the end of the second month after today's) and
      whose payment is not past due gets an expectation when it has none, so the cash flow ahead shows.
    * An unfulfilled expectation follows its forecast as long as the forecast has an amount, also
      past its due date: the payment may have been made without linking it.
    * An unfulfilled expectation of the last year, the current one or the one the horizon reaches whose forecast has no amount any
      more, or is gone because the settings changed, is removed.
    * A fulfilled expectation is never touched.
  """
  alias Firmowid.Finances.ExpectedTransaction
  alias Firmowid.Taxes.Forecast.Period

  @type forecast :: %{
          required(:kind) => :vat | :cit | :pit | :zus,
          required(:period) => String.t(),
          required(:period_start) => Date.t(),
          required(:amount) => Decimal.t(),
          required(:due_date) => Date.t(),
          required(:description) => String.t(),
          required(:member_id) => String.t() | nil,
          optional(atom()) => term()
        }

  @type attributes :: %{
          forecast_key: String.t(),
          date: Date.t(),
          amount: Money.t(),
          description: String.t(),
          counterparty_name: String.t()
        }

  @type operation ::
          {:create, attributes()}
          | {:update, ExpectedTransaction.t(), %{date: Date.t(), amount: Money.t(), description: String.t()}}
          | {:destroy, ExpectedTransaction.t()}

  @doc "Returns the operations that bring `existing` expectations in step with `forecasts` as of `today`."
  @spec plan([forecast()], [ExpectedTransaction.t()], Date.t()) :: [operation()]
  def plan(forecasts, existing, today) do
    existing = Enum.filter(existing, & &1.forecast_key)
    by_key = Map.new(existing, &{&1.forecast_key, &1})
    payable = Enum.filter(forecasts, &Decimal.gt?(&1.amount, 0))
    payable_keys = MapSet.new(payable, &key/1)
    horizon = Period.horizon(today)
    years = Enum.uniq([today.year - 1, today.year, horizon.year])

    creates =
      for forecast <- payable,
          not is_map_key(by_key, key(forecast)),
          not Date.after?(forecast.period_start, horizon),
          not Date.before?(forecast.due_date, today),
          do: {:create, attributes(forecast)}

    updates =
      for forecast <- payable,
          %{is_fulfilled: false} = record <- [by_key[key(forecast)]],
          changes = changes(record, attributes(forecast)),
          do: {:update, record, changes}

    destroys =
      for %{is_fulfilled: false} = record <- existing,
          year_of(record.forecast_key) in years,
          not MapSet.member?(payable_keys, record.forecast_key),
          do: {:destroy, record}

    creates ++ updates ++ destroys
  end

  # The same period of the same kind (and owner) is one payment, so one expectation.
  defp key(%{kind: kind, period: period, member_id: nil}), do: "#{kind}:#{period}"

  defp key(%{kind: kind, period: period, member_id: member_id}), do: "#{kind}:#{period}:#{member_id}"

  defp attributes(forecast) do
    %{
      forecast_key: key(forecast),
      date: forecast.due_date,
      amount: Money.new!(:PLN, Decimal.negate(forecast.amount)),
      description: forecast.description,
      counterparty_name: counterparty_name(forecast.kind)
    }
  end

  defp counterparty_name(:zus), do: "ZUS"
  defp counterparty_name(_tax), do: "Urząd Skarbowy"

  # nil when the expectation already shows the forecast.
  defp changes(record, attributes) do
    changes = Map.take(attributes, [:date, :amount, :description])

    if Date.compare(record.date, changes.date) == :eq and
         Money.equal?(record.amount, changes.amount) and
         record.description == changes.description,
       do: nil,
       else: changes
  end

  # The year of the key's period: `2026` in `vat:2026-11` and `cit:2026-Q4`.
  defp year_of(forecast_key) do
    [_kind, period | _owner] = String.split(forecast_key, ":")
    period |> String.slice(0, 4) |> String.to_integer()
  end
end
