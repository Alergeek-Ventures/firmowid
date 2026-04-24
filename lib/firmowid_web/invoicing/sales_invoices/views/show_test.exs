# credo:disable-for-this-file ExDNA.Credo
defmodule FirmowidWeb.Invoicing.SalesInvoices.Views.ShowTest do
  @moduledoc false
  use FirmowidWeb.ConnCase

  import Firmowid.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Firmowid.Ash.Finances.Transaction
  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Scope

  test "shows recommendation, links transaction, and allows unlinking", %{conn: conn} do
    admin = admin_fixture()
    invoice = sales_invoice_fixture!(admin)
    transaction = matching_transaction_fixture!(admin, invoice)
    conn = log_in_user(conn, admin)

    {:ok, view, html} = live(conn, ~p"/sprzedazowe/#{invoice.id}")

    assert html =~ "Potencjalne transakcje dla dokumentu"
    assert html =~ "Payment January"
    refute html =~ "Dopasowanie"

    connect_html =
      view
      |> element("button[phx-click='connect']")
      |> render_click()

    assert connect_html =~ "Dopasowanie"

    linked_invoice =
      Invoicing.get_sales_invoice!(invoice.id,
        load: [:transactions],
        scope: scope_for(admin)
      )

    assert Enum.map(linked_invoice.transactions, & &1.id) == [transaction.id]

    view
    |> element("#invoice-show button[phx-click='disconnect']")
    |> render_click()

    html_after_disconnect = render(view)

    assert html_after_disconnect =~ "Potencjalne transakcje dla dokumentu"
    assert html_after_disconnect =~ "Payment January"
    refute html_after_disconnect =~ "Dopasowanie"

    unlinked_invoice =
      Invoicing.get_sales_invoice!(invoice.id,
        load: [:transactions],
        scope: scope_for(admin)
      )

    assert unlinked_invoice.transactions == []
  end

  test "allows skipping invoice from details", %{conn: conn} do
    admin = admin_fixture()
    invoice = sales_invoice_fixture!(admin)
    conn = log_in_user(conn, admin)

    {:ok, view, html} = live(conn, ~p"/sprzedazowe/#{invoice.id}")

    assert html =~ "Pomiń"

    skipped_html =
      view
      |> element("button", "Pomiń")
      |> render_click()

    assert skipped_html =~ "Transakcja pominięta"

    skipped_invoice =
      Invoicing.get_sales_invoice!(invoice.id, scope: scope_for(admin))

    assert skipped_invoice.skip_invoicing
  end

  defp sales_invoice_fixture!(admin) do
    {:ok, invoice} =
      SalesInvoice.create(
        %{
          invoice_number: "FV/SHOW/#{System.unique_integer([:positive])}",
          issue_date: ~D[2026-01-10],
          sale_date: ~D[2026-01-10],
          due_date: ~D[2026-01-24],
          payment_method: :transfer,
          invoice_type: :foreign,
          currency: "EUR",
          seller_nip: "6161525811",
          seller_display_name: "Bytecraft",
          seller_address: "Address",
          buyer_type: :company,
          buyer_id: "1111111111",
          buyer_full_name: "Acme Corp",
          buyer_display_name: "Acme Corp",
          buyer_address: "Buyer address",
          buyer_country: "PL",
          sales_invoice_items: [
            %{
              index: 0,
              name: "Line",
              quantity: Decimal.new("1"),
              unit: "szt",
              unit_price: Decimal.new("100"),
              vat_rate: "23"
            }
          ]
        },
        tenant: admin.organization_id,
        actor: admin
      )

    Invoicing.get_sales_invoice!(invoice.id,
      load: [:gross_value, :buyer_display_name_label],
      scope: scope_for(admin)
    )
  end

  defp matching_transaction_fixture!(admin, invoice) do
    Ash.Seed.seed!(Transaction, %{
      transaction_id: "TX-SHOW-#{System.unique_integer([:positive])}",
      internal_transaction_id: "INT-TX-SHOW-#{System.unique_integer([:positive])}",
      creditor_name: "Bytecraft",
      creditor_account: "PL02114020040000300201355387",
      debtor_name: "Acme",
      debtor_account: "PL61109010140000071219812874",
      transaction_amount: invoice.gross_value,
      transaction_currency: invoice.currency,
      booking_date: invoice.issue_date,
      value_date: invoice.issue_date,
      remittance_information_unstructured: "Payment January",
      organization_id: admin.organization_id
    })
  end

  defp scope_for(user) do
    %Scope{actor: user, tenant: user.organization_id}
  end
end
