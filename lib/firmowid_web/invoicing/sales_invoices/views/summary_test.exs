defmodule FirmowidWeb.Invoicing.SalesInvoices.Views.SummaryTest do
  use FirmowidWeb.ConnCase

  import Firmowid.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Firmowid.InvoicingFixtures
  alias FirmowidWeb.Invoicing.Utilities.Navigation

  describe "Invoice page works" do
    setup do
      on_exit(fn -> Cachex.clear(:ksef) end)
    end

    test "renders sales_invoices page", %{conn: conn} do
      conn = log_in_user(conn, admin_fixture())

      # Creator creates a WizardState in shared ETS on connect,
      # then push_patches to ?szkic_kreatora=<id>&krok=1
      {:ok, lv, _html} = live(conn, ~p"/sprzedazowe")
      html = render(lv)

      assert html =~ "Wybierz kontrahenta"
    end

    test "redirects if user is not logged in", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/sprzedazowe")

      assert {:redirect, %{to: path}} = redirect
      assert path == ~p"/zaloguj"
    end

    test "does not expose an active edit control for a locked invoice without a KSeF number", %{
      conn: conn
    } do
      admin = admin_fixture()
      invoice = sales_invoice_fixture!(admin)
      Ash.Seed.update!(invoice, %{locked_at: DateTime.utc_now()})
      conn = log_in_user(conn, admin)

      {:ok, _view, html} = live(conn, ~p"/sprzedazowe/#{invoice.id}/podsumowanie")

      assert html =~ ~s(id="edit-invoice-button")
      assert html =~ ~s(disabled)
      refute html =~ ~s(href="/sprzedazowe/#{invoice.id}/edytuj")
    end

    test "updates summary after failed status broadcast", %{conn: conn} do
      admin = admin_fixture()
      InvoicingFixtures.connect_ksef!(admin.member.organization_id)
      invoice = sales_invoice_fixture!(admin)
      conn = log_in_user(conn, admin)

      {:ok, view, html} = live(conn, ~p"/sprzedazowe/#{invoice.id}/podsumowanie")

      assert html =~ "Faktura wystawiona"

      # The submission worker returns an invoice KSeF did not accept to a draft.
      Ash.Seed.update!(invoice, %{
        invoice_number: nil,
        ksef_session_reference_number: "REF-#{System.unique_integer([:positive])}"
      })

      send(view.pid, {:ksef_invoice_status, %{invoice_id: invoice.id, status: :failed}})

      assert render(view) =~ "Wysyłka do KSeF nie powiodła się"
      assert has_element?(view, "#returned-to-draft-notice")
      assert has_element?(view, ~s(a[href="/sprzedazowe/#{invoice.id}/edytuj"]))
    end

    test "preserves return_to in summary navigation links", %{conn: conn} do
      admin = admin_fixture()

      invoice =
        admin
        |> sales_invoice_fixture!()
        |> Ash.Seed.update!(%{
          ksef_number: "KSEF-ACCEPTED",
          ksef_invoice_checksum: "accepted-hash"
        })

      conn = log_in_user(conn, admin)

      origin_return_to =
        Navigation.return_to_path("/fakturowanie?miesiac=2026-01-15&filtr=faktury&widok=lista")

      transaction_return_to = Navigation.transaction_show_path("tx-123", origin_return_to)

      {:ok, _view, html} =
        live(conn, Navigation.sales_invoice_summary_path(invoice, transaction_return_to))

      assert html =~
               ~s(href="#{Navigation.sales_invoice_edit_path(invoice, transaction_return_to)}")

      assert html =~
               ~s(href="#{Navigation.sales_invoice_show_path(invoice, transaction_return_to)}")
    end
  end

  defp scope_for(user) do
    %Firmowid.Scope{actor: user, tenant: user.member.organization_id}
  end

  defp sales_invoice_fixture!(admin) do
    {:ok, invoice} =
      InvoicingFixtures.seed_sales_invoice(
        %{
          invoice_number: "FV/SUMMARY/#{System.unique_integer([:positive])}",
          issue_date: ~D[2026-01-10],
          sale_date: ~D[2026-01-10],
          due_date: ~D[2026-01-24],
          payment_method: :transfer,
          seller_account_number: "PL61109010140000071219812874",
          invoice_type: :foreign,
          currency: "EUR",
          seller_nip: "6161525811",
          seller_display_name: "Bytecraft",
          seller_address: "Address",
          buyer_type: :company,
          buyer_id: "1111111111",
          buyer_full_name: "Buyer Company",
          buyer_display_name: "Buyer Company",
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
        tenant: admin.member.organization_id,
        actor: admin
      )

    invoice
  end
end
