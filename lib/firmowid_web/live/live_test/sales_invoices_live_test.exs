defmodule FirmowidWeb.SalesInvoicesLiveTest do
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures
  import Phoenix.LiveViewTest

  describe "Invoice page works" do
    test "renders sales_invoices page", %{conn: conn} do
      conn = log_in_user(conn, admin_fixture())

      # Creator redirects to draft URL, follow it
      {:ok, _lv, html} =
        conn
        |> live(~p"/sprzedazowe")
        |> follow_redirect(conn)

      assert html =~ "Wybierz kontrahenta"
    end

    test "redirects if user is not logged in", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/sprzedazowe")

      assert {:redirect, %{to: path}} = redirect
      assert path == ~p"/zaloguj"
    end
  end
end
