defmodule FirmowidWeb.SalesInvoicesLiveTest do
  use FirmowidWeb.ConnCase, async: true

  alias Firmowid.SalesInvoices

  import Phoenix.LiveViewTest
  import Firmowid.AccountsFixtures

  describe "Invoice page works" do
    test "renders sales_invoices page", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/sales_invoices")

      assert html =~ "Rodzaj faktury"
    end

    test "redirects if user is not logged in", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/sales_invoices")

      assert {:redirect, %{to: path}} = redirect
      assert path == ~p"/users/log_in"
    end
  end

  describe "basic info" do
    setup %{conn: conn} do
      password = valid_user_password()
      user = user_fixture(%{password: password})
      %{conn: log_in_user(conn, user)}
    end

    test "makes section confirmed", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/sales_invoices")
      invoice_number = "Numer mojej faktury"

      result =
        lv
        |> form("#basic_info_form",
          sales_invoice: %{
            "invoice_number" => invoice_number
          }
        )
        |> render_submit()

      assert result =~ invoice_number
      assert SalesInvoices.get_latest_sales_invoice().invoice_number == invoice_number
    end
  end

  describe "seller form" do
    setup %{conn: conn} do
      password = valid_user_password()
      user = user_fixture(%{password: password})
      %{conn: log_in_user(conn, user)}
    end

    test "adds seller but doesnt confirm", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/sales_invoices")

      form =
        lv
        |> form("#seller_form",
          sales_invoice: %{
            "seller_display_name" => "Franciszkowo",
            "seller_name" => "Franek",
            "seller_surname" => "Madej",
            "seller_address" => "ul. Testowa 1",
            "seller_nip" => "1234567890",
            "seller_account_number" => "1234567890"
          }
        )

      result =
        form
        |> put_submitter("button[name=action]")
        |> render_submit

      assert result =~ "Franek"
      assert result =~ "Zatwierdź"

      seller = SalesInvoices.list_sellers() |> hd

      assert seller.name == "Franek"

      assert SalesInvoices.get_latest_sales_invoice().is_seller_confirmed == false
      assert SalesInvoices.get_latest_sales_invoice().seller_id == seller.id
    end

    test "adds seller and confirms", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/sales_invoices")

      form =
        lv
        |> form("#seller_form",
          sales_invoice: %{
            "seller_display_name" => "Franciszkowo",
            "seller_name" => "Franek",
            "seller_surname" => "Madej",
            "seller_address" => "ul. Testowa 1",
            "seller_nip" => "1234567890",
            "seller_account_number" => "1234567890"
          }
        )

      form
      |> put_submitter("button[name=action]")
      |> render_submit

      result =
        form
        |> put_submitter("#seller_confirm_button")
        |> render_submit()

      assert result =~ "Franek"

      assert SalesInvoices.get_latest_sales_invoice().is_seller_confirmed == true
      assert SalesInvoices.get_latest_sales_invoice().seller_name == "Franek"
    end
  end

  describe "buyer form" do
    setup %{conn: conn} do
      password = valid_user_password()
      user = user_fixture(%{password: password})
      %{conn: log_in_user(conn, user)}
    end

    test "adds buyer via nip", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/sales_invoices")

      lv |> element("#buyer_expand_button") |> render_click()

      lv
      |> form("#buyer_nip_form",
        nip: "6793209719"
      )
      |> render_submit()

      result =
        lv
        |> form("#buyer_form")
        |> put_submitter("button[name=action]")
        |> render_submit

      buyer = SalesInvoices.list_buyers() |> hd

      assert result =~ "ALERGEEK VENTURES"
      assert result =~ "Zatwierdź"
      assert buyer.display_name == "ALERGEEK VENTURES SPÓŁKA Z OGRANICZONĄ ODPOWIEDZIALNOŚCIĄ"

      assert SalesInvoices.get_latest_sales_invoice().is_buyer_confirmed == false
      assert SalesInvoices.get_latest_sales_invoice().buyer_id == buyer.id
    end
  end

  describe "invoice items" do
    setup %{conn: conn} do
      password = valid_user_password()
      user = user_fixture(%{password: password})
      %{conn: log_in_user(conn, user)}
    end

    test "adds invoice item and confirm it", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/sales_invoices")

      # Add new invoice item
      lv
      |> element("#invoice_items_form")
      |> render_change(%{"sales_invoice[items_sort][]" => "new"})

      result =
        lv
        |> form("#invoice_items_form",
          sales_invoice: %{
            "invoice_items" => %{
              "0" => %{
                "name" => "Koszty utrzymania",
                "unit" => "godz.",
                "unit_price" => "100",
                "vat_rate" => "23",
                "quantity" => "1"
              }
            }
          }
        )
        |> render_submit

      assert result =~ "Koszty utrzymania"
      # Make sure that form is confirmed and locked
      refute lv |> element("#invoice_items_form") |> render =~ "Zatwierdź"

      invoice_item = SalesInvoices.get_latest_sales_invoice().invoice_items |> hd

      assert invoice_item.name == "Koszty utrzymania"
      assert invoice_item.unit_price == Decimal.new("100")
      assert invoice_item.vat_rate == Decimal.new("23")
      assert invoice_item.quantity == Decimal.new("1")
    end
  end
end
