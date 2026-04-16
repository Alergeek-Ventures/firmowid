defmodule FirmowidWeb.Invoicing.SalesInvoices.Utilities.PaymentDateSuggestions do
  @moduledoc """
  Builds and applies quick date suggestions for sales invoice payment forms.
  """

  @type suggestion_target :: :sale_date | :due_date
  @type suggestion_key ::
          :today
          | :end_of_previous_month
          | :days_3
          | :days_7
          | :days_30
          | :end_of_current_month

  @sale_date_suggestions [
    {"today", "dzisiaj"},
    {"end_of_previous_month", "ostatni dzień ubiegłego miesiąca"}
  ]

  @due_date_suggestions [
    {"days_3", "3 dni"},
    {"days_7", "7 dni"},
    {"days_30", "30 dni"},
    {"end_of_current_month", "koniec obecnego miesiąca"}
  ]

  @doc """
  Returns available sale date suggestions.
  """
  @spec sale_date_suggestions() :: [{String.t(), String.t()}]
  def sale_date_suggestions, do: @sale_date_suggestions

  @doc """
  Parses a payment date field name used by the UI.
  """
  @spec parse_target(String.t()) :: suggestion_target() | nil
  def parse_target("sale_date"), do: :sale_date
  def parse_target("due_date"), do: :due_date
  def parse_target(_), do: nil

  @doc """
  Returns available due date suggestions.
  """
  @spec due_date_suggestions() :: [{String.t(), String.t()}]
  def due_date_suggestions, do: @due_date_suggestions

  @doc """
  Parses a suggestion key used by the UI.
  """
  @spec parse_suggestion(String.t()) :: suggestion_key() | nil
  def parse_suggestion("today"), do: :today
  def parse_suggestion("end_of_previous_month"), do: :end_of_previous_month
  def parse_suggestion("days_3"), do: :days_3
  def parse_suggestion("days_7"), do: :days_7
  def parse_suggestion("days_30"), do: :days_30
  def parse_suggestion("end_of_current_month"), do: :end_of_current_month
  def parse_suggestion(_), do: nil

  @doc """
  Applies a date suggestion to payment form params.

  Due-date day offsets are counted from the invoice issue date.
  The end-of-current-month suggestion uses the real current month.
  """
  @spec apply_suggestion(map(), suggestion_target(), suggestion_key(), Date.t(), Date.t()) :: map()
  def apply_suggestion(params, target, suggestion, issue_date, today \\ Date.utc_today()) do
    date = suggested_date(target, suggestion, issue_date, today)

    Map.put(params, Atom.to_string(target), Date.to_iso8601(date))
  end

  defp suggested_date(:sale_date, :today, _issue_date, today), do: today

  defp suggested_date(:sale_date, :end_of_previous_month, _issue_date, today) do
    today
    |> Date.beginning_of_month()
    |> Date.add(-1)
  end

  defp suggested_date(:due_date, :days_3, issue_date, _today), do: Date.add(issue_date, 3)
  defp suggested_date(:due_date, :days_7, issue_date, _today), do: Date.add(issue_date, 7)
  defp suggested_date(:due_date, :days_30, issue_date, _today), do: Date.add(issue_date, 30)
  defp suggested_date(:due_date, :end_of_current_month, _issue_date, today), do: Date.end_of_month(today)
end
