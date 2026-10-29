defmodule FirmowidWeb.Delegations.Utilities.SettlementForm do
  @moduledoc "Builds and normalizes the nested delegation settlement form."

  import Phoenix.Component, only: [to_form: 1]

  alias AshMoney.Types.Money, as: MoneyType
  alias AshPhoenix.Form.Auto
  alias Firmowid.Delegations.DelegationExpense.Trip
  alias Phoenix.HTML.Form

  @doc "Builds the complete form for a delegation settlement."
  @spec complete_form(struct(), map(), atom()) :: Form.t()
  def complete_form(delegation, scope, action \\ :complete) do
    forms =
      Firmowid.Delegations.Delegation
      |> Auto.auto(action)
      |> Enum.map(fn {key, config} ->
        config =
          config |> Keyword.fetch!(:updater) |> then(& &1.(config)) |> Keyword.delete(:updater)

        if key == :expenses do
          {key,
           config
           |> ticket_input_forms()
           |> Keyword.put(:transform_params, fn params, _type ->
             transform_expense_params(params)
           end)}
        else
          {key, config}
        end
      end)

    delegation
    |> AshPhoenix.Form.for_update(action, scope: scope, as: "delegation", forms: forms)
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

  @doc "Reconciles unsaved expense inputs by identity after documents are added or removed."
  @spec preserve_expense_params(Form.t(), map()) :: map()
  def preserve_expense_params(form, params) do
    previous = params |> Map.get("expenses", %{}) |> Map.values() |> Map.new(&{&1["id"], &1})

    expenses =
      form
      |> nested_forms(:expenses)
      |> Enum.with_index()
      |> Map.new(fn {expense, index} ->
        initial = %{
          "id" => expense.data.id,
          "_form_type" => "update",
          "expense_amount" => Decimal.to_string(Money.to_decimal(expense.data.expense_amount), :normal),
          "details" => %{"_union_type" => Atom.to_string(expense.data.details.type)}
        }

        {to_string(index), Map.get(previous, expense.data.id, initial)}
      end)

    Map.put(params, "expenses", expenses)
  end

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
        expense = Map.drop(expense, ["settlement_method", "nbp_rate", "nbp_rate_date"])

        expense =
          case Map.get(modes, expense["id"]) do
            :statement ->
              expense
              |> Map.put("settlement_method", "statement")
              |> Map.put("settlement_currency", "PLN")

            :nbp ->
              put_nbp_settlement(expense, Map.get(nbp_settlements, expense["id"]))

            nil ->
              drop_settlement_amount(expense)
          end

        {index, expense}
      end)
    end)
  end

  defp transform_expense_params(%{"kind" => kind} = params) do
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

  defp transform_expense_params(%{"details" => details} = params) do
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
      nil ->
        nil

      %{"amount" => _amount} = amount ->
        if currency, do: Map.put(amount, "currency", currency), else: amount

      amount ->
        %{"amount" => amount, "currency" => currency || "PLN"}
    end)
  end

  # Applies the server-calculated rate to the submitted amount, and only while it
  # is still in the currency the rate was fetched for.
  defp put_nbp_settlement(expense, settlement) do
    amount_params = normalize_expense_amount(expense)["expense_amount"]

    with %{source_currency: source_currency, rate: rate, date: date} <- settlement,
         {:ok, %Money{} = amount} <- Ash.Type.cast_input(MoneyType, amount_params),
         true <- Atom.to_string(Money.to_currency_code(amount)) == source_currency do
      expense
      |> Map.put("settlement_method", "nbp")
      |> Map.put(
        "settlement_amount",
        Decimal.to_string(Decimal.mult(Money.to_decimal(amount), rate), :normal)
      )
      |> Map.put("settlement_currency", "PLN")
      |> Map.put("nbp_rate", Decimal.to_string(rate, :normal))
      |> Map.put("nbp_rate_date", Date.to_iso8601(date))
    else
      _ -> drop_settlement_amount(expense)
    end
  end

  defp drop_settlement_amount(expense) do
    expense
    |> Map.delete("settlement_currency")
    |> Map.merge(%{
      "settlement_amount" => nil,
      "settlement_method" => nil,
      "nbp_rate" => nil,
      "nbp_rate_date" => nil
    })
  end

  defp nested_forms(%Form{source: source}, field),
    do: source.forms |> Map.get(field, []) |> List.wrap() |> Enum.map(&to_form/1)

  defp nested_form(%Form{source: %{forms: forms}}, field), do: forms |> Map.fetch!(field) |> to_form()

  defp ticket_input_forms(config) do
    Keyword.update!(config, :forms, fn forms ->
      Keyword.update!(forms, :details, fn details ->
        updater = Keyword.fetch!(details, :updater)

        Keyword.put(details, :updater, fn options, data, params ->
          options = updater.(options, data, params)

          Keyword.update(options, :forms, [], fn forms ->
            Enum.map(forms, fn
              {:trips, trip_options} ->
                {:trips, Keyword.put(trip_options, :transform_params, &trip_action_params/3)}

              other ->
                other
            end)
          end)
        end)
      end)
    end)
  end

  # Keep the raw date/time parts in the form draft, but never send virtual inputs to Ash.
  defp trip_action_params(form, params, _type) do
    if Map.has_key?(params, "departure_time") || Map.has_key?(params, "arrival_time") do
      params
      |> put_trip_datetime(:departure, form.data)
      |> put_trip_datetime(:arrival, form.data)
      |> Map.drop(["departure_date", "departure_time", "arrival_date", "arrival_time"])
    else
      params
    end
  end

  defp put_trip_datetime(params, prefix, original) do
    date = params["#{prefix}_date"]
    time = params["#{prefix}_time"]

    cond do
      unchanged_ticket_time?(params, prefix, original) ->
        # An unrelated edit must not infer local time for a legacy record or lose a known DST offset.
        Map.drop(params, ["#{prefix}_local_datetime", "#{prefix}_datetime"])

      date in [nil, ""] && time in [nil, ""] ->
        params |> Map.put("#{prefix}_local_datetime", nil) |> Map.put("#{prefix}_datetime", nil)

      true ->
        params
        |> Map.put("#{prefix}_local_datetime", local_datetime_value(date, time))
        |> Map.put("#{prefix}_datetime", nil)
    end
  end

  defp unchanged_ticket_time?(_params, _prefix, nil), do: false

  defp unchanged_ticket_time?(params, prefix, original) do
    previous = Trip.local_datetime(original, prefix)

    previous && params["#{prefix}_date"] == Calendar.strftime(previous, "%Y-%m-%d") &&
      params["#{prefix}_time"] == Calendar.strftime(previous, "%H:%M") &&
      params["#{prefix}_city"] == Map.fetch!(original, city_field(prefix))
  end

  defp local_datetime_value(date, time) when is_binary(date) and is_binary(time) do
    date <> "T" <> time <> ":00"
  end

  defp local_datetime_value(_date, _time), do: "incomplete"

  defp city_field(:departure), do: :departure_city
  defp city_field(:arrival), do: :arrival_city
end
