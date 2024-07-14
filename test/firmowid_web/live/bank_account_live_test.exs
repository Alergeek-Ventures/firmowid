defmodule FirmowidWeb.BankAccountLiveTest do
  use FirmowidWeb.ConnCase

  import Phoenix.LiveViewTest
  import Firmowid.FinancesFixtures

  @create_attrs %{iban: "some iban"}
  @update_attrs %{iban: "some updated iban"}
  @invalid_attrs %{iban: nil}

  defp create_bank_account(_) do
    bank_account = bank_account_fixture()
    %{bank_account: bank_account}
  end

  describe "Index" do
    setup [:create_bank_account]

    test "lists all bank_accounts", %{conn: conn, bank_account: bank_account} do
      {:ok, _index_live, html} = live(conn, ~p"/bank_accounts")

      assert html =~ "Listing Bank accounts"
      assert html =~ bank_account.iban
    end

    test "saves new bank_account", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/bank_accounts")

      assert index_live |> element("a", "New Bank account") |> render_click() =~
               "New Bank account"

      assert_patch(index_live, ~p"/bank_accounts/new")

      assert index_live
             |> form("#bank_account-form", bank_account: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#bank_account-form", bank_account: @create_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/bank_accounts")

      html = render(index_live)
      assert html =~ "Bank account created successfully"
      assert html =~ "some iban"
    end

    test "updates bank_account in listing", %{conn: conn, bank_account: bank_account} do
      {:ok, index_live, _html} = live(conn, ~p"/bank_accounts")

      assert index_live |> element("#bank_accounts-#{bank_account.id} a", "Edit") |> render_click() =~
               "Edit Bank account"

      assert_patch(index_live, ~p"/bank_accounts/#{bank_account}/edit")

      assert index_live
             |> form("#bank_account-form", bank_account: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#bank_account-form", bank_account: @update_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/bank_accounts")

      html = render(index_live)
      assert html =~ "Bank account updated successfully"
      assert html =~ "some updated iban"
    end

    test "deletes bank_account in listing", %{conn: conn, bank_account: bank_account} do
      {:ok, index_live, _html} = live(conn, ~p"/bank_accounts")

      assert index_live |> element("#bank_accounts-#{bank_account.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#bank_accounts-#{bank_account.id}")
    end
  end

  describe "Show" do
    setup [:create_bank_account]

    test "displays bank_account", %{conn: conn, bank_account: bank_account} do
      {:ok, _show_live, html} = live(conn, ~p"/bank_accounts/#{bank_account}")

      assert html =~ "Show Bank account"
      assert html =~ bank_account.iban
    end

    test "updates bank_account within modal", %{conn: conn, bank_account: bank_account} do
      {:ok, show_live, _html} = live(conn, ~p"/bank_accounts/#{bank_account}")

      assert show_live |> element("a", "Edit") |> render_click() =~
               "Edit Bank account"

      assert_patch(show_live, ~p"/bank_accounts/#{bank_account}/show/edit")

      assert show_live
             |> form("#bank_account-form", bank_account: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert show_live
             |> form("#bank_account-form", bank_account: @update_attrs)
             |> render_submit()

      assert_patch(show_live, ~p"/bank_accounts/#{bank_account}")

      html = render(show_live)
      assert html =~ "Bank account updated successfully"
      assert html =~ "some updated iban"
    end
  end
end
