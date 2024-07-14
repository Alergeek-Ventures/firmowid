defmodule FirmowidWeb.ImportedTransactionLiveTest do
  use FirmowidWeb.ConnCase

  import Phoenix.LiveViewTest
  import Firmowid.FinancesFixtures

  @create_attrs %{transaction_id: "some transaction_id", debtor_name: "some debtor_name", debtor_account: "some debtor_account", transaction_amount: 120.5, transaction_currency: "some transaction_currency", bank_transaction_code: "some bank_transaction_code", booking_date: "2024-07-13", value_date: "2024-07-13", remittance_information_unstructured: "some remittance_information_unstructured"}
  @update_attrs %{transaction_id: "some updated transaction_id", debtor_name: "some updated debtor_name", debtor_account: "some updated debtor_account", transaction_amount: 456.7, transaction_currency: "some updated transaction_currency", bank_transaction_code: "some updated bank_transaction_code", booking_date: "2024-07-14", value_date: "2024-07-14", remittance_information_unstructured: "some updated remittance_information_unstructured"}
  @invalid_attrs %{transaction_id: nil, debtor_name: nil, debtor_account: nil, transaction_amount: nil, transaction_currency: nil, bank_transaction_code: nil, booking_date: nil, value_date: nil, remittance_information_unstructured: nil}

  defp create_imported_transaction(_) do
    imported_transaction = imported_transaction_fixture()
    %{imported_transaction: imported_transaction}
  end

  describe "Index" do
    setup [:create_imported_transaction]

    test "lists all imported_transactions", %{conn: conn, imported_transaction: imported_transaction} do
      {:ok, _index_live, html} = live(conn, ~p"/imported_transactions")

      assert html =~ "Listing Imported transactions"
      assert html =~ imported_transaction.transaction_id
    end

    test "saves new imported_transaction", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/imported_transactions")

      assert index_live |> element("a", "New Imported transaction") |> render_click() =~
               "New Imported transaction"

      assert_patch(index_live, ~p"/imported_transactions/new")

      assert index_live
             |> form("#imported_transaction-form", imported_transaction: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#imported_transaction-form", imported_transaction: @create_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/imported_transactions")

      html = render(index_live)
      assert html =~ "Imported transaction created successfully"
      assert html =~ "some transaction_id"
    end

    test "updates imported_transaction in listing", %{conn: conn, imported_transaction: imported_transaction} do
      {:ok, index_live, _html} = live(conn, ~p"/imported_transactions")

      assert index_live |> element("#imported_transactions-#{imported_transaction.id} a", "Edit") |> render_click() =~
               "Edit Imported transaction"

      assert_patch(index_live, ~p"/imported_transactions/#{imported_transaction}/edit")

      assert index_live
             |> form("#imported_transaction-form", imported_transaction: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#imported_transaction-form", imported_transaction: @update_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/imported_transactions")

      html = render(index_live)
      assert html =~ "Imported transaction updated successfully"
      assert html =~ "some updated transaction_id"
    end

    test "deletes imported_transaction in listing", %{conn: conn, imported_transaction: imported_transaction} do
      {:ok, index_live, _html} = live(conn, ~p"/imported_transactions")

      assert index_live |> element("#imported_transactions-#{imported_transaction.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#imported_transactions-#{imported_transaction.id}")
    end
  end

  describe "Show" do
    setup [:create_imported_transaction]

    test "displays imported_transaction", %{conn: conn, imported_transaction: imported_transaction} do
      {:ok, _show_live, html} = live(conn, ~p"/imported_transactions/#{imported_transaction}")

      assert html =~ "Show Imported transaction"
      assert html =~ imported_transaction.transaction_id
    end

    test "updates imported_transaction within modal", %{conn: conn, imported_transaction: imported_transaction} do
      {:ok, show_live, _html} = live(conn, ~p"/imported_transactions/#{imported_transaction}")

      assert show_live |> element("a", "Edit") |> render_click() =~
               "Edit Imported transaction"

      assert_patch(show_live, ~p"/imported_transactions/#{imported_transaction}/show/edit")

      assert show_live
             |> form("#imported_transaction-form", imported_transaction: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert show_live
             |> form("#imported_transaction-form", imported_transaction: @update_attrs)
             |> render_submit()

      assert_patch(show_live, ~p"/imported_transactions/#{imported_transaction}")

      html = render(show_live)
      assert html =~ "Imported transaction updated successfully"
      assert html =~ "some updated transaction_id"
    end
  end
end
