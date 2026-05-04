# credo:disable-for-this-file ExDNA.Credo
defmodule FirmowidWeb.Invoicing.Transactions.Views.ShowTest do
  @moduledoc false
  use FirmowidWeb.ConnCase

  import Firmowid.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Firmowid.Ash.Finances.Transaction
  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Invoicing.CostInvoiceTransaction
  alias FirmowidWeb.Invoicing.Navigation

  test "shows zero state for an unmatched transaction", %{conn: conn} do
    admin = admin_fixture()

    transaction =
      transaction_fixture!(admin, %{remittance_information_unstructured: "Unmatched payment"})

    conn = log_in_user(conn, admin)

    {:ok, view, html} = live(conn, ~p"/transakcje/#{transaction.id}")

    assert has_element?(view, "#transaction-show", "Brak rekomendacji")

    assert has_element?(
             view,
             "#transaction-show",
             "Firmowid nie znalazł jeszcze żadnych faktur, które potencjalnie pasowałyby do tej transakcji."
           )

    assert has_element?(view, "#transaction-show button[phx-click='toggle-invoicing']", "Pomiń")

    refute html =~ "Dopasowanie"
    refute html =~ "Transakcja pominięta"
  end

  test "shows skipped state for a skipped transaction", %{conn: conn} do
    admin = admin_fixture()
    transaction = transaction_fixture!(admin, %{skip_invoicing: true})
    conn = log_in_user(conn, admin)

    {:ok, view, html} = live(conn, ~p"/transakcje/#{transaction.id}")

    assert has_element?(view, "#transaction-show", "Transakcja pominięta")

    assert has_element?(
             view,
             "#transaction-show",
             "Transakcja została pominięta w dopasowywaniu. Przywróć ją, jeśli jednak chcesz połączyć ją z dokumentem."
           )

    assert has_element?(view, "#transaction-show button[phx-click='toggle-invoicing']")

    refute html =~ "Brak rekomendacji"
    refute html =~ "Dopasowanie"
  end

  test "shows connected view when the transaction is linked to an invoice", %{conn: conn} do
    admin = admin_fixture()

    transaction =
      transaction_fixture!(admin, %{
        remittance_information_unstructured: "Supplier payment January"
      })

    invoice = cost_invoice_fixture!(admin)
    link_transaction_to_cost_invoice!(admin, transaction, invoice)
    conn = log_in_user(conn, admin)

    {:ok, view, html} = live(conn, ~p"/transakcje/#{transaction.id}")

    assert has_element?(view, "#transaction-show", "Dopasowanie")
    assert has_element?(view, "#transaction-show", "Komplet")
    assert has_element?(view, "#transaction-show", invoice.invoice_identifier)
    assert has_element?(view, "#transaction-show", invoice.seller_display_name)
    assert has_element?(view, "#transaction-show", "Faktura kosztowa")
    assert has_element?(view, "#transaction-show button[phx-click='unlink_all']")

    refute html =~ "Brak rekomendacji"
    refute html =~ "Transakcja pominięta"
  end

  test "uses an allowlisted return_to path for back navigation", %{conn: conn} do
    admin = admin_fixture()

    transaction =
      transaction_fixture!(admin, %{
        remittance_information_unstructured: "Back navigation payment"
      })

    conn = log_in_user(conn, admin)

    {:ok, _view, html} =
      live(
        conn,
        ~p"/transakcje/#{transaction.id}?#{[return_to: "/fakturowanie?month=2026-01-15&filter=invoices&view=list"]}"
      )

    assert html =~
             ~s(href="/fakturowanie?month=2026-01-01&amp;filter=invoices&amp;view=list")
  end

  test "preserves transaction return context in linked invoice navigation", %{conn: conn} do
    admin = admin_fixture()

    transaction =
      transaction_fixture!(admin, %{remittance_information_unstructured: "Linked return flow"})

    invoice = cost_invoice_fixture!(admin)
    link_transaction_to_cost_invoice!(admin, transaction, invoice)
    conn = log_in_user(conn, admin)

    raw_origin_return_to = "/fakturowanie?month=2026-01-15&filter=invoices&view=list"
    origin_return_to = Navigation.return_to_path(raw_origin_return_to)
    transaction_return_to = Navigation.transaction_show_path(transaction, origin_return_to)
    expected_invoice_path = Navigation.cost_invoice_show_path(invoice, transaction_return_to)

    {:ok, _view, html} =
      live(conn, ~p"/transakcje/#{transaction.id}?#{[return_to: raw_origin_return_to]}")

    assert html =~ ~s(href="#{expected_invoice_path}")
  end

  test "ignores a non-allowlisted return_to path for back navigation", %{conn: conn} do
    admin = admin_fixture()
    transaction = transaction_fixture!(admin, %{booking_date: ~D[2026-01-10]})
    conn = log_in_user(conn, admin)

    {:ok, _view, html} =
      live(conn, ~p"/transakcje/#{transaction.id}?#{[return_to: "https://example.com"]}")

    assert html =~ ~s(href="/fakturowanie?month=2026-01-01&amp;filter=all")
    refute html =~ "https://example.com"
  end

  defp transaction_fixture!(admin, attrs) do
    unique = System.unique_integer([:positive])

    defaults = %{
      transaction_id: "TX-SHOW-#{unique}",
      internal_transaction_id: "INT-TX-SHOW-#{unique}",
      creditor_name: "Supplier Sp. z o.o.",
      creditor_account: "PL02114020040000300201355387",
      debtor_name: "Firmowid Sp. z o.o.",
      debtor_account: "PL61109010140000071219812874",
      transaction_amount: Decimal.new("-100.00"),
      transaction_currency: "PLN",
      booking_date: ~D[2026-01-10],
      value_date: ~D[2026-01-10],
      remittance_information_unstructured: "Payment January",
      skip_invoicing: false,
      organization_id: admin.organization_id
    }

    Ash.Seed.seed!(Transaction, Map.merge(defaults, attrs))
  end

  defp cost_invoice_fixture!(admin) do
    Ash.Seed.seed!(CostInvoice, %{
      seller: "Supplier Sp. z o.o.",
      seller_display_name: "Supplier Sp. z o.o.",
      invoice_identifier: "CI/SHOW/#{System.unique_integer([:positive])}",
      description: "Cost invoice show test",
      sale_date: ~D[2026-01-10],
      issue_date: ~D[2026-01-10],
      due_date: ~D[2026-01-24],
      total_amount: Decimal.new("-100.00"),
      currency: "PLN",
      skip_invoicing: false,
      organization_id: admin.organization_id
    })
  end

  defp link_transaction_to_cost_invoice!(admin, transaction, invoice) do
    Ash.Seed.seed!(CostInvoiceTransaction, %{
      cost_invoice_id: invoice.id,
      transaction_id: transaction.id,
      organization_id: admin.organization_id
    })
  end
end
