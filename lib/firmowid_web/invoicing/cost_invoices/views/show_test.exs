# credo:disable-for-this-file ExDNA.Credo
defmodule FirmowidWeb.Invoicing.CostInvoices.Views.ShowTest do
  @moduledoc false
  use FirmowidWeb.ConnCase

  import Firmowid.AccountsFixtures
  import Firmowid.FinancesFixtures
  import Phoenix.LiveViewTest

  alias Firmowid.Ash.Finances.Transaction
  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Scope
  alias FirmowidWeb.Invoicing.Utilities.Navigation

  test "shows recommendation, links transaction, and allows unlinking", %{conn: conn} do
    admin = admin_fixture()
    invoice = cost_invoice_fixture!(admin)
    transaction = matching_transaction_fixture!(admin, invoice)
    conn = log_in_user(conn, admin)

    {:ok, view, html} = live(conn, ~p"/kosztowe/#{invoice.id}")

    assert html =~ "Potencjalne transakcje dla dokumentu"
    assert html =~ "Supplier payment January"
    refute html =~ "Dopasowanie"

    connect_html =
      view
      |> element("button[phx-click='connect']")
      |> render_click()

    assert connect_html =~ "Dopasowanie"

    linked_invoice =
      Invoicing.get_cost_invoice!(invoice.id,
        load: [:transactions],
        scope: scope_for(admin)
      )

    assert Enum.map(linked_invoice.transactions, & &1.id) == [transaction.id]

    view
    |> element("#invoice-show button[phx-click='disconnect']")
    |> render_click()

    html_after_disconnect = render(view)

    assert html_after_disconnect =~ "Potencjalne transakcje dla dokumentu"
    assert html_after_disconnect =~ "Supplier payment January"
    refute html_after_disconnect =~ "Dopasowanie"

    unlinked_invoice =
      Invoicing.get_cost_invoice!(invoice.id,
        load: [:transactions],
        scope: scope_for(admin)
      )

    assert unlinked_invoice.transactions == []
  end

  test "shows flash when transaction connect fails", %{conn: conn} do
    admin = admin_fixture()
    invoice = cost_invoice_fixture!(admin)
    transaction = matching_transaction_fixture!(admin, invoice)
    conn = log_in_user(conn, admin)

    {:ok, view, _html} = live(conn, ~p"/kosztowe/#{invoice.id}")

    failed_html =
      view
      |> element("button[phx-click='connect']")
      |> render_click(%{"transaction_id" => Ash.UUID.generate()})

    assert failed_html =~ "Nie udało się połączyć transakcji"

    reloaded_invoice =
      Invoicing.get_cost_invoice!(invoice.id,
        load: [:transactions],
        scope: scope_for(admin)
      )

    assert reloaded_invoice.transactions == []
    assert transaction.id
  end

  test "allows skipping invoice from details", %{conn: conn} do
    admin = admin_fixture()
    invoice = cost_invoice_fixture!(admin)
    conn = log_in_user(conn, admin)

    {:ok, view, html} = live(conn, ~p"/kosztowe/#{invoice.id}")

    assert html =~ "Pomiń"

    skipped_html =
      view
      |> element("button", "Pomiń")
      |> render_click()

    assert skipped_html =~ "Transakcja pominięta"

    skipped_invoice =
      Invoicing.get_cost_invoice!(invoice.id, scope: scope_for(admin))

    assert skipped_invoice.skip_invoicing
  end

  test "preserves transaction return context for back navigation", %{conn: conn} do
    admin = admin_fixture()
    invoice = cost_invoice_fixture!(admin)
    conn = log_in_user(conn, admin)

    origin_return_to =
      Navigation.return_to_path("/fakturowanie?miesiac=2026-01-15&filtr=faktury&widok=lista")

    transaction_return_to = Navigation.transaction_show_path("tx-123", origin_return_to)

    {:ok, _view, html} =
      live(conn, Navigation.cost_invoice_show_path(invoice, transaction_return_to))

    assert html =~ ~s(href="#{transaction_return_to}")
  end

  test "renders the internal note as readonly text and saves changes", %{conn: conn} do
    admin = admin_fixture()
    invoice = cost_invoice_fixture!(admin)
    conn = log_in_user(conn, admin)

    {:ok, view, _html} = live(conn, ~p"/kosztowe/#{invoice.id}")

    assert has_element?(view, "#internal-note-input[readonly]")

    view
    |> form("#internal-note-form", %{"internal_note" => "Notatka zespołu"})
    |> render_change()

    updated_invoice = Invoicing.get_cost_invoice!(invoice.id, scope: scope_for(admin))
    assert updated_invoice.internal_note == "Notatka zespołu"
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
      amount: Money.new!("PLN", Decimal.new("-100.00")),
      skip_invoicing: false,
      organization_id: admin.organization_id
    })
  end

  defp matching_transaction_fixture!(admin, invoice) do
    Ash.Seed.seed!(Transaction, %{
      transaction_id: "TX-COST-SHOW-#{System.unique_integer([:positive])}",
      internal_transaction_id: "INT-TX-COST-SHOW-#{System.unique_integer([:positive])}",
      creditor_name: invoice.seller_display_name,
      creditor_account: "PL02114020040000300201355387",
      debtor_name: "Our Company",
      debtor_account: "PL61109010140000071219812874",
      amount: invoice.amount,
      booking_date: invoice.issue_date,
      value_date: invoice.issue_date,
      remittance_information_unstructured: "Supplier payment January",
      bank_account_id: bank_account_fixture!(admin).id,
      organization_id: admin.organization_id
    })
  end

  defp scope_for(user) do
    %Scope{actor: user, tenant: user.organization_id}
  end
end
