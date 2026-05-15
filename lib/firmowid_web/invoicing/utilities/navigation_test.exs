defmodule FirmowidWeb.Invoicing.Utilities.NavigationTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias FirmowidWeb.Invoicing.Utilities.Navigation

  test "parse_return_target/1 returns a typed invoicing index target" do
    assert Navigation.parse_return_target("/fakturowanie?miesiac=2026-01-15&filtr=faktury&widok=lista") ==
             {:invoicing_index, %{month: ~D[2026-01-15], filter: :invoices, subfilter: nil, view_mode: :list}}
  end

  test "return_to_path/1 rebuilds an allowlisted invoicing path" do
    assert Navigation.return_to_path("/fakturowanie?miesiac=2026-01-15&filtr=faktury&widok=lista") ==
             "/fakturowanie?miesiac=2026-01-01&filtr=faktury&widok=lista"
  end

  test "return_to_path/1 rebuilds the last sales invoices path" do
    assert Navigation.return_to_path("/sprzedazowe?karta=ostatnie_faktury") ==
             "/sprzedazowe?karta=ostatnie_faktury"
  end

  test "return_to_path/1 rebuilds an allowlisted transaction details path" do
    return_to =
      Navigation.transaction_show_path(
        "tx-123",
        "/fakturowanie?miesiac=2026-01-15&filtr=faktury&widok=lista"
      )

    assert Navigation.return_to_path(return_to) ==
             "/transakcje/tx-123?powrot_do=%2Ffakturowanie%3Fmiesiac%3D2026-01-01%26filtr%3Dfaktury%26widok%3Dlista"
  end

  test "transaction_show_path/2 preserves an allowlisted return destination" do
    assert Navigation.transaction_show_path(
             "tx-123",
             "/fakturowanie?miesiac=2026-01-01&filtr=wszystkie"
           ) ==
             "/transakcje/tx-123?powrot_do=%2Ffakturowanie%3Fmiesiac%3D2026-01-01%26filtr%3Dwszystkie"
  end

  test "transaction_show_path/2 accepts typed return targets" do
    return_target =
      {:invoicing_index, %{month: ~D[2026-01-15], filter: :all, subfilter: nil, view_mode: :dashboard}}

    assert Navigation.transaction_show_path("tx-123", return_target) ==
             "/transakcje/tx-123?powrot_do=%2Ffakturowanie%3Fmiesiac%3D2026-01-01%26filtr%3Dwszystkie"
  end

  test "sales invoice navigation helpers preserve nested return destinations" do
    return_to =
      Navigation.transaction_show_path(
        "tx-123",
        "/fakturowanie?miesiac=2026-01-01&filtr=wszystkie"
      )

    assert Navigation.sales_invoice_show_path("inv-123", return_to) ==
             "/sprzedazowe/inv-123?powrot_do=#{URI.encode_www_form(return_to)}"

    assert Navigation.sales_invoice_edit_path("inv-123", return_to) ==
             "/sprzedazowe/inv-123/edytuj?powrot_do=#{URI.encode_www_form(return_to)}"

    assert Navigation.sales_invoice_summary_path("inv-123", return_to) ==
             "/sprzedazowe/inv-123/podsumowanie?powrot_do=#{URI.encode_www_form(return_to)}"

    assert Navigation.cost_invoice_show_path("inv-123", return_to) ==
             "/kosztowe/inv-123?powrot_do=#{URI.encode_www_form(return_to)}"
  end

  test "transaction_show_path/2 omits empty return destinations" do
    assert Navigation.transaction_show_path("tx-123", nil) == "/transakcje/tx-123"
    assert Navigation.transaction_show_path("tx-123", "") == "/transakcje/tx-123"
  end

  test "default_invoicing_path/1 returns the dashboard view for the month" do
    assert Navigation.default_invoicing_path(~D[2026-01-15]) ==
             "/fakturowanie?miesiac=2026-01-01&filtr=wszystkie"
  end

  test "return_to_path/1 rejects non-allowlisted destinations" do
    assert Navigation.return_to_path("https://example.com") == nil
    assert Navigation.return_to_path("/sprzedazowe?karta=wszystkie") == nil
    assert Navigation.return_to_path("/fakturowanie?miesiac=2026-01-01") == nil

    assert Navigation.return_to_path("/transakcje/tx-123?powrot_do=#{URI.encode_www_form("https://example.com")}") == nil
  end
end
