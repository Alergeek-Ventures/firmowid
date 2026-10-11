# credo:disable-for-this-file ExDNA.Credo
defmodule FirmowidWeb.Invoicing.Transactions.Views.ShowTest do
  @moduledoc false
  use FirmowidWeb.ConnCase

  import Firmowid.AccountsFixtures
  import Firmowid.FinancesFixtures
  import Phoenix.LiveViewTest

  alias Firmowid.Ash.Finances.Transaction
  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Invoicing.CostInvoiceTransaction
  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Invoicing.SalesInvoiceItem
  alias Firmowid.Ash.Scope
  alias FirmowidWeb.Invoicing.Utilities.Navigation

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

  test "suggests tenant-owned cost invoices and confirms and undoes a match from the transaction",
       %{conn: conn} do
    admin = admin_fixture()
    scope = Scope.new!(admin, admin.organization_id)
    transaction = transaction_fixture!(admin, %{})
    invoice = cost_invoice_fixture!(admin)
    skipped = cost_invoice_fixture!(admin, %{skip_invoicing: true})
    foreign = cost_invoice_fixture!(admin_fixture())
    conn = log_in_user(conn, admin)

    {:ok, view, _html} = live(conn, ~p"/transakcje/#{transaction.id}")

    assert has_element?(view, "#invoice-suggestions", invoice.invoice_identifier)
    refute has_element?(view, "#invoice-suggestion-#{skipped.id}")
    refute has_element?(view, "#invoice-suggestion-#{foreign.id}")
    refute has_element?(view, "#transaction-show", "Brak rekomendacji")

    view
    |> element("#invoice-suggestion-#{invoice.id} button", "Zatwierdź")
    |> render_click()

    assert has_element?(view, "#transaction-show", "Komplet")
    refute has_element?(view, "#invoice-suggestions")

    assert %{transactions: [%{id: transaction_id}]} =
             Invoicing.get_cost_invoice!(invoice.id, load: [:transactions], scope: scope)

    assert transaction_id == transaction.id

    view |> element("button[phx-click='unlink_all']") |> render_click()

    assert has_element?(view, "#invoice-suggestions", invoice.invoice_identifier)
  end

  test "suggests confirmed sales invoices for an incoming transaction and confirms the match", %{
    conn: conn
  } do
    admin = admin_fixture()
    scope = Scope.new!(admin, admin.organization_id)

    transaction =
      transaction_fixture!(admin, %{
        amount: Money.new!(:PLN, 123),
        debtor_name: "Example customer"
      })

    invoice = sales_invoice_fixture!(admin)
    draft = sales_invoice_fixture!(admin, %{invoice_number: nil})
    conn = log_in_user(conn, admin)

    {:ok, view, _html} = live(conn, ~p"/transakcje/#{transaction.id}")

    assert has_element?(view, "#invoice-suggestions", invoice.invoice_number)
    refute has_element?(view, "#invoice-suggestion-#{draft.id}")

    view
    |> element("#invoice-suggestion-#{invoice.id} button", "Zatwierdź")
    |> render_click()

    assert has_element?(view, "#transaction-show", "Komplet")
    assert has_element?(view, "#transaction-show", "Faktura sprzedażowa")

    assert %{transactions: [%{id: transaction_id}]} =
             Invoicing.get_sales_invoice!(invoice.id, load: [:transactions], scope: scope)

    assert transaction_id == transaction.id
  end

  test "uses an allowlisted return_to path for back navigation", %{conn: conn} do
    admin = admin_fixture()

    transaction =
      transaction_fixture!(admin, %{
        remittance_information_unstructured: "Back navigation payment"
      })

    conn = log_in_user(conn, admin)
    raw_return_to = "/fakturowanie?miesiac=2026-01-15&filtr=faktury&widok=lista"
    origin_return_to = Navigation.return_to_path(raw_return_to)

    {:ok, _view, html} =
      live(
        conn,
        ~p"/transakcje/#{transaction.id}?#{[powrot_do: raw_return_to]}"
      )

    assert html =~ ~s(href="#{String.replace(origin_return_to, "&", "&amp;")}")
  end

  test "preserves transaction return context in linked invoice navigation", %{conn: conn} do
    admin = admin_fixture()

    transaction =
      transaction_fixture!(admin, %{remittance_information_unstructured: "Linked return flow"})

    invoice = cost_invoice_fixture!(admin)
    link_transaction_to_cost_invoice!(admin, transaction, invoice)
    conn = log_in_user(conn, admin)

    raw_origin_return_to = "/fakturowanie?miesiac=2026-01-15&filtr=faktury&widok=lista"
    origin_return_to = Navigation.return_to_path(raw_origin_return_to)
    transaction_return_to = Navigation.transaction_show_path(transaction, origin_return_to)
    expected_invoice_path = Navigation.cost_invoice_show_path(invoice, transaction_return_to)

    {:ok, _view, html} =
      live(conn, ~p"/transakcje/#{transaction.id}?#{[powrot_do: raw_origin_return_to]}")

    assert html =~ ~s(href="#{expected_invoice_path}")
  end

  test "ignores a non-allowlisted return_to path for back navigation", %{conn: conn} do
    admin = admin_fixture()
    transaction = transaction_fixture!(admin, %{booking_date: ~D[2026-01-10]})
    conn = log_in_user(conn, admin)

    {:ok, _view, html} =
      live(conn, ~p"/transakcje/#{transaction.id}?#{[powrot_do: "https://example.com"]}")

    default_return_to =
      ~D[2026-01-10]
      |> Navigation.default_invoicing_path()
      |> String.replace("&", "&amp;")

    assert html =~ ~s(href="#{default_return_to}")
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
      amount: Money.new!("PLN", Decimal.new("-100.00")),
      booking_date: ~D[2026-01-10],
      value_date: ~D[2026-01-10],
      remittance_information_unstructured: "Payment January",
      bank_account_id: bank_account_fixture!(admin).id,
      skip_invoicing: false,
      organization_id: admin.organization_id
    }

    Ash.Seed.seed!(Transaction, Map.merge(defaults, attrs))
  end

  defp cost_invoice_fixture!(admin, attrs \\ %{}) do
    defaults = %{
      seller: "Supplier Sp. z o.o.",
      seller_display_name: "Supplier Sp. z o.o.",
      invoice_identifier: "CI/SHOW/#{System.unique_integer([:positive])}",
      description: "Cost invoice show test",
      sale_date: ~D[2026-01-10],
      issue_date: ~D[2026-01-10],
      due_date: ~D[2026-01-24],
      amount: Money.new!("PLN", Decimal.new("-100.00")),
      skip_invoicing: false,
      organization_id: admin.organization_id
    }

    Ash.Seed.seed!(CostInvoice, Map.merge(defaults, attrs))
  end

  defp sales_invoice_fixture!(admin, attrs \\ %{}) do
    invoice =
      Ash.Seed.seed!(
        SalesInvoice,
        Map.merge(
          %{
            invoice_number: "SI/SHOW/#{System.unique_integer([:positive])}",
            issue_date: ~D[2026-01-10],
            sale_date: ~D[2026-01-10],
            due_date: ~D[2026-01-24],
            currency: "PLN",
            buyer_full_name: "Example customer",
            seller_account_number: "PL61109010140000071219812874",
            organization_id: admin.organization_id
          },
          attrs
        )
      )

    Ash.Seed.seed!(SalesInvoiceItem, %{
      sales_invoice_id: invoice.id,
      organization_id: admin.organization_id,
      index: 0,
      name: "Programming service",
      quantity: Decimal.new(1),
      unit: "szt.",
      unit_price: Decimal.new(100),
      vat_rate: "23"
    })

    invoice
  end

  defp link_transaction_to_cost_invoice!(admin, transaction, invoice) do
    Ash.Seed.seed!(CostInvoiceTransaction, %{
      cost_invoice_id: invoice.id,
      transaction_id: transaction.id,
      organization_id: admin.organization_id
    })
  end
end
