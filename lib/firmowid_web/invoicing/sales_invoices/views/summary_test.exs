defmodule FirmowidWeb.Invoicing.SalesInvoices.Views.SummaryTest do
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures
  import Phoenix.LiveViewTest

  describe "Invoice page works" do
    test "renders sales_invoices page", %{conn: conn} do
      conn = log_in_user(conn, admin_fixture())

      # Creator creates a WizardDraft in process-local ETS on connect,
      # then push_patches to ?creator_draft=<id>&step=1
      {:ok, lv, _html} = live(conn, ~p"/sprzedazowe")
      html = render(lv)

      assert html =~ "Wybierz kontrahenta"
    end

    test "redirects if user is not logged in", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/sprzedazowe")

      assert {:redirect, %{to: path}} = redirect
      assert path == ~p"/zaloguj"
    end
  end
end
