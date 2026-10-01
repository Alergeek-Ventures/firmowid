defmodule FirmowidWeb.Delegations.Utilities.SettlementForm do
  @moduledoc "Builds and normalizes the nested delegation settlement form."

  import Phoenix.Component, only: [to_form: 1]

  alias AshPhoenix.Form.Auto
  alias Firmowid.Ash.Currencies.NbpApiClient
  alias Phoenix.HTML.Form

  @doc "Builds the complete form for a delegation settlement."
  @spec complete_form(struct(), map(), String.t()) :: Form.t()
  def complete_form(delegation, scope, timezone) do
    forms =
      Firmowid.Ash.Delegations.Delegation
      |> Auto.auto(:complete)
      |> Enum.map(fn {key, config} ->
        config =
          config |> Keyword.fetch!(:updater) |> then(& &1.(config)) |> Keyword.delete(:updater)

        if key == :expenses do
          {key,
           Keyword.put(config, :transform_params, fn params, _type ->
             transform_expense_params(params, timezone)
           end)}
        else
          {key, config}
        end
      end)

    delegation
    |> AshPhoenix.Form.for_update(:complete, scope: scope, as: "delegation", forms: forms)
    |> to_form()
  end

  @doc "Returns the nested forms indexed by their expense and trip identifiers."
  @spec nested_forms(Form.t()) :: %{expense_forms: map(), trip_forms: map()}
  def nested_forms(form) do
    expense_forms =
      form
      |> nested_forms(:expenses)
      |> Map.new(&{&1.data.id, %{expense: &1, details: nested_form(&1, :details)}})

    trip_forms =
      expense_forms
      |> Map.values()
      |> Enum.flat_map(&nested_forms(&1.details, :trips))
      |> Map.new(&{&1.data.id, &1})

    %{expense_forms: expense_forms, trip_forms: trip_forms}
  end

  @doc "Converts the browser's date and time fields into UTC timestamps."
  @spec transform_trip_datetimes(map() | list(), String.t()) :: map() | list()
  def transform_trip_datetimes(params, timezone) when is_map(params) do
    params =
      Map.new(params, fn {key, value} -> {key, transform_trip_datetimes(value, timezone)} end)

    if Map.has_key?(params, "departure_time") || Map.has_key?(params, "arrival_time") do
      params
      |> put_trip_datetime("departure", timezone)
      |> put_trip_datetime("arrival", timezone)
      |> Map.drop(["departure_date", "departure_time", "arrival_date", "arrival_time"])
    else
      params
    end
  end

  def transform_trip_datetimes(params, timezone) when is_list(params),
    do: Enum.map(params, &transform_trip_datetimes(&1, timezone))

  def transform_trip_datetimes(params, _timezone), do: params

  @doc "Adds selected expense currencies to nested form parameters."
  @spec merge_expense_currencies(map(), map()) :: map()
  def merge_expense_currencies(params, expense_currencies) do
    Map.update(params, "expenses", %{}, fn expenses ->
      Map.new(expenses, fn {index, expense} ->
        {index, Map.put(expense, "expense_currency", Map.get(expense_currencies, expense["id"], "PLN"))}
      end)
    end)
  end

  @doc "Adds the chosen foreign-currency settlement values to nested form parameters."
  @spec merge_foreign_currency_settlements(map(), map(), map()) :: map()
  def merge_foreign_currency_settlements(params, modes, nbp_settlements) do
    Map.update(params, "expenses", %{}, fn expenses ->
      Map.new(expenses, fn {index, expense} ->
        expense =
          case Map.get(modes, expense["id"]) do
            :statement ->
              expense
              |> Map.put("settlement_method", "statement")
              |> Map.put("settlement_currency", "PLN")

            :nbp ->
              put_nbp_settlement(expense, Map.get(nbp_settlements, expense["id"]))

            _ ->
              expense
          end

        {index, expense}
      end)
    end)
  end

  @doc "Calculates the NBP settlement amount for an expense form."
  @spec nbp_settlement(map(), map(), String.t(), String.t()) ::
          {:ok, map()} | {:error, :rate_unavailable}
  def nbp_settlement(expense_forms, expense_currencies, expense_id, target_currency) do
    with true <- target_currency == "PLN" or NbpApiClient.supported_currency?(target_currency),
         %{expense: form} <- Map.fetch!(expense_forms, expense_id),
         %Money{} = amount <- form[:expense_amount].value,
         source_currency = Map.get(expense_currencies, expense_id, "PLN"),
         date = Date.utc_today(),
         {:ok, source_rate} <- nbp_rate(source_currency, date),
         {:ok, target_rate} <- nbp_rate(target_currency, date) do
      rate = source_rate |> Decimal.div(target_rate) |> Decimal.round(4)

      {:ok,
       %{
         amount: Money.new(target_currency, Decimal.mult(Money.to_decimal(amount), rate)),
         rate: rate,
         date: date
       }}
    else
      _ -> {:error, :rate_unavailable}
    end
  end

  defp transform_expense_params(%{"kind" => kind} = params, _timezone) do
    details =
      case kind do
        "transport" ->
          %{
            "type" => kind,
            "transport_type" => params["transport_type"] || "other",
            "trips" => []
          }

        "accommodation" ->
          params
          |> Map.take(["locality", "arrival_date", "departure_date", "description"])
          |> Map.put("type", kind)

        "other" ->
          params |> Map.take(["description"]) |> Map.put("type", kind)
      end

    params
    |> Map.take([
      "id",
      "_form_type",
      "document_number",
      "expense_amount",
      "expense_currency",
      "settlement_method",
      "settlement_amount",
      "settlement_currency",
      "nbp_rate",
      "nbp_rate_date"
    ])
    |> normalize_expense_amount()
    |> normalize_settlement_amount()
    |> Map.put("details", details)
  end

  defp transform_expense_params(%{"details" => details} = params, _timezone) do
    params
    |> Map.take([
      "id",
      "_form_type",
      "document_number",
      "expense_amount",
      "expense_currency",
      "settlement_method",
      "settlement_amount",
      "settlement_currency",
      "nbp_rate",
      "nbp_rate_date"
    ])
    |> normalize_expense_amount()
    |> normalize_settlement_amount()
    |> Map.put("details", details)
  end

  defp normalize_expense_amount(params), do: normalize_amount(params, "expense_amount", "expense_currency")

  defp normalize_settlement_amount(params), do: normalize_amount(params, "settlement_amount", "settlement_currency")

  defp normalize_amount(params, amount_key, currency_key) do
    currency = Map.get(params, currency_key)

    params
    |> Map.delete(currency_key)
    |> Map.update(amount_key, nil, fn
      %{"amount" => _amount} = amount ->
        if currency, do: Map.put(amount, "currency", currency), else: amount

      amount ->
        %{"amount" => amount, "currency" => currency || "PLN"}
    end)
  end

  defp put_nbp_settlement(expense, %{amount: amount, rate: rate, date: date}) do
    expense
    |> Map.put("settlement_method", "nbp")
    |> Map.put("settlement_amount", Decimal.to_string(Money.to_decimal(amount), :normal))
    |> Map.put("settlement_currency", "PLN")
    |> Map.put("nbp_rate", Decimal.to_string(rate, :normal))
    |> Map.put("nbp_rate_date", Date.to_iso8601(date))
  end

  defp put_nbp_settlement(expense, nil), do: expense

  defp nested_forms(%Form{source: source}, field),
    do: source.forms |> Map.get(field, []) |> List.wrap() |> Enum.map(&to_form/1)

  defp nested_form(%Form{source: %{forms: forms}}, field), do: forms |> Map.fetch!(field) |> to_form()

  defp put_trip_datetime(params, prefix, timezone) do
    with date when is_binary(date) <- params["#{prefix}_date"],
         time when is_binary(time) <- params["#{prefix}_time"],
         {:ok, date} <- Date.from_iso8601(date),
         {:ok, time} <- Time.from_iso8601(time <> ":00"),
         {:ok, datetime} <- DateTime.new(date, time, timezone) do
      datetime = DateTime.shift_zone!(datetime, "Etc/UTC")
      Map.put(params, "#{prefix}_datetime", DateTime.to_iso8601(datetime))
    else
      _ -> params
    end
  end

  defp nbp_rate("PLN", _date), do: {:ok, Decimal.new(1)}

  defp nbp_rate(currency, date) do
    case NbpApiClient.get_exchange_rate(currency, date) do
      {:ok, %{rate: rate}} -> {:ok, Decimal.from_float(rate)}
      {:error, _reason} -> {:error, :rate_unavailable}
    end
  end
end
