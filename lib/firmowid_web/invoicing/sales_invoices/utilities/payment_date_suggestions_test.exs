defmodule FirmowidWeb.Invoicing.SalesInvoices.Utilities.PaymentDateSuggestionsTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias FirmowidWeb.Invoicing.SalesInvoices.Utilities.PaymentDateSuggestions

  test "sale date suggestions use current-day context" do
    today = ~D[2026-04-16]

    assert PaymentDateSuggestions.apply_suggestion(%{}, :sale_date, :today, ~D[2026-04-10], today) ==
             %{"sale_date" => "2026-04-16"}

    assert PaymentDateSuggestions.apply_suggestion(
             %{},
             :sale_date,
             :end_of_previous_month,
             ~D[2026-04-10],
             today
           ) == %{"sale_date" => "2026-03-31"}
  end

  test "due date suggestions use issue date for day offsets" do
    issue_date = ~D[2026-04-10]

    assert PaymentDateSuggestions.apply_suggestion(%{}, :due_date, :days_3, issue_date) ==
             %{"due_date" => "2026-04-13"}

    assert PaymentDateSuggestions.apply_suggestion(%{}, :due_date, :days_7, issue_date) ==
             %{"due_date" => "2026-04-17"}

    assert PaymentDateSuggestions.apply_suggestion(%{}, :due_date, :days_30, issue_date) ==
             %{"due_date" => "2026-05-10"}
  end

  test "end of current month uses the real current month" do
    today = ~D[2026-04-16]

    assert PaymentDateSuggestions.apply_suggestion(
             %{},
             :due_date,
             :end_of_current_month,
             ~D[2026-02-01],
             today
           ) == %{"due_date" => "2026-04-30"}
  end
end
