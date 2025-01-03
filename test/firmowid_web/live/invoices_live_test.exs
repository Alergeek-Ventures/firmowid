defmodule FirmowidWeb.InvoicesLiveTest do
  use FirmowidWeb.ConnCase, async: true

  alias Firmowid.Invoices

  import Phoenix.LiveViewTest
  import Firmowid.AccountsFixtures

  describe "Invoice page works" do
    test "renders invoices page", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/invoices")

      assert html =~ "Rodzaj faktury"
    end

    test "redirects if user is not logged in", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/invoices")

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
      {:ok, lv, _html} = live(conn, ~p"/invoices")
      invoice_number = "Numer mojej faktury"

      result =
        lv
        |> form("#basic_info_form",
          invoice: %{
            "invoice_number" => invoice_number
          }
        )
        |> render_submit()

      assert result =~ invoice_number
      assert Invoices.get_latest_invoice().invoice_number == invoice_number
    end
  end

  describe "seller form" do
    setup %{conn: conn} do
      password = valid_user_password()
      user = user_fixture(%{password: password})
      %{conn: log_in_user(conn, user)}
    end

    test "adds seller but doesnt confirm", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/invoices")

      form =
        lv
        |> form("#seller_form",
          invoice: %{
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

      seller = Invoices.list_sellers() |> hd

      assert seller.name == "Franek"

      assert Invoices.get_latest_invoice().is_seller_confirmed == false
      assert Invoices.get_latest_invoice().seller_id == seller.id
    end

    test "adds seller and confirms", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/invoices")

      form =
        lv
        |> form("#seller_form",
          invoice: %{
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

      assert Invoices.get_latest_invoice().is_seller_confirmed == true
      assert Invoices.get_latest_invoice().seller_name == "Franek"
    end
  end

  describe "buyer form" do
    setup %{conn: conn} do
      password = valid_user_password()
      user = user_fixture(%{password: password})
      %{conn: log_in_user(conn, user)}
    end

    test "adds buyer via nip", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/invoices")

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

      buyer = Invoices.list_buyers() |> hd

      assert result =~ "ALERGEEK VENTURES"
      assert result =~ "Zatwierdź"
      assert buyer.display_name == "ALERGEEK VENTURES SPÓŁKA Z OGRANICZONĄ ODPOWIEDZIALNOŚCIĄ"

      assert Invoices.get_latest_invoice().is_buyer_confirmed == false
      assert Invoices.get_latest_invoice().buyer_id == buyer.id
    end
  end
end
