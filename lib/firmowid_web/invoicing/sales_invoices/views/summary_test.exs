defmodule FirmowidWeb.Invoicing.SalesInvoices.Views.SummaryTest do
  use FirmowidWeb.ConnCase

  import Firmowid.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Ksef.Credential
  alias FirmowidWeb.Invoicing.Utilities.Navigation

  describe "Invoice page works" do
    setup do
      original_ksef_config = Application.fetch_env!(:firmowid, :ksef)

      Application.put_env(
        :firmowid,
        :ksef,
        Keyword.merge(original_ksef_config,
          base_url: "https://ksef.example",
          request_options: [plug: {Req.Test, :ksef_api}]
        )
      )

      on_exit(fn ->
        Application.put_env(:firmowid, :ksef, original_ksef_config)
        Cachex.clear(:ksef)
      end)

      :ok
    end

    test "renders sales_invoices page", %{conn: conn} do
      conn = log_in_user(conn, admin_fixture())

      # Creator creates a WizardDraft in process-local ETS on connect,
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

    test "shows KSeF send action for connected organization and ready invoice", %{conn: conn} do
      admin = admin_fixture()
      seed_ksef_credential!(admin.organization_id)
      invoice = sales_invoice_fixture!(admin)
      conn = log_in_user(conn, admin)

      {:ok, _view, html} = live(conn, ~p"/sprzedazowe/#{invoice.id}/podsumowanie")

      assert html =~ "Faktura wystawiona"
      assert html =~ "Wyślij do KSeF"
    end

    test "updates summary after failed status broadcast", %{conn: conn} do
      admin = admin_fixture()
      seed_ksef_credential!(admin.organization_id)
      invoice = sales_invoice_fixture!(admin)
      conn = log_in_user(conn, admin)

      {:ok, view, html} = live(conn, ~p"/sprzedazowe/#{invoice.id}/podsumowanie")

      assert html =~ "Faktura wystawiona"

      Ash.Seed.update!(invoice, %{
        ksef_session_reference_number: "REF-#{System.unique_integer([:positive])}"
      })

      send(view.pid, {:ksef_invoice_status, %{invoice_id: invoice.id, status: :failed}})

      updated_html = render(view)

      assert updated_html =~ "Wysyłka do KSeF nie powiodła się"
      assert updated_html =~ "Przejdź do faktury"
    end

    test "clicking send to KSeF submits invoice through mocked API", %{conn: conn} do
      admin = admin_fixture()
      seed_ksef_credential!(admin.organization_id)
      seed_ksef_access_token!(admin.organization_id)
      seed_ksef_public_key!()
      invoice = sales_invoice_fixture!(admin)

      Req.Test.stub(:ksef_api, fn conn ->
        case {conn.method, conn.request_path} do
          {"POST", "/sessions/online"} ->
            Req.Test.json(Plug.Conn.put_status(conn, 201), %{"referenceNumber" => "SESSION-REF-1"})

          {"POST", "/sessions/online/SESSION-REF-1/invoices"} ->
            Req.Test.json(Plug.Conn.put_status(conn, 202), %{"referenceNumber" => "INVOICE-REF-1"})

          {"POST", "/sessions/online/SESSION-REF-1/close"} ->
            Plug.Conn.send_resp(conn, 204, "")

          {"GET", "/sessions/SESSION-REF-1/invoices/INVOICE-REF-1"} ->
            Req.Test.json(conn, %{
              "status" => %{"code" => 200},
              "ksefNumber" => "KSEF-#{System.unique_integer([:positive])}",
              "acquisitionDate" => "2026-01-10T12:00:00Z",
              "invoiceHash" => "verified-hash"
            })

          _ ->
            Plug.Conn.send_resp(
              conn,
              404,
              "unexpected request: #{conn.method} #{conn.request_path}"
            )
        end
      end)

      conn = log_in_user(conn, admin)

      {:ok, view, html} = live(conn, ~p"/sprzedazowe/#{invoice.id}/podsumowanie")

      assert html =~ "Wyślij do KSeF"

      view
      |> element("button[phx-click='send_to_ksef']")
      |> render_click()

      Process.sleep(50)

      submitted_invoice = Invoicing.get_sales_invoice!(invoice.id, scope: scope_for(admin))
      assert submitted_invoice.ksef_number
      assert submitted_invoice.ksef_invoice_checksum == "verified-hash"

      {:ok, _remounted_view, remounted_html} =
        live(conn, ~p"/sprzedazowe/#{invoice.id}/podsumowanie")

      assert remounted_html =~ "Faktura wysłana do KSeF"
      assert remounted_html =~ "Wysłano do KSeF!"
    end

    test "preserves return_to in summary navigation links", %{conn: conn} do
      admin = admin_fixture()
      invoice = sales_invoice_fixture!(admin)
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
    %Firmowid.Ash.Scope{actor: user, tenant: user.organization_id}
  end

  defp sales_invoice_fixture!(admin) do
    {:ok, invoice} =
      SalesInvoice.create(
        %{
          invoice_number: "FV/SUMMARY/#{System.unique_integer([:positive])}",
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
        tenant: admin.organization_id,
        actor: admin
      )

    invoice
  end

  defp seed_ksef_credential!(organization_id) do
    Ash.Seed.seed!(Credential, %{
      organization_id: organization_id,
      status: :working,
      auth_type: :token,
      credentials: "token-#{System.unique_integer([:positive])}"
    })
  end

  defp seed_ksef_access_token!(organization_id) do
    token = build_jwt_with_exp(DateTime.shift(DateTime.utc_now(), minute: 5))
    Cachex.put(:ksef, {:access_token, organization_id}, token, expire: to_timeout(minute: 5))
  end

  defp seed_ksef_public_key! do
    private_key = X509.PrivateKey.new_rsa(2048)
    certificate = X509.Certificate.self_signed(private_key, "/CN=KSeF Test")

    Cachex.put(:ksef, {:public_key, "SymmetricKeyEncryption"}, certificate)
  end

  defp build_jwt_with_exp(expires_at) do
    header = %{"alg" => "none", "typ" => "JWT"}
    payload = %{"exp" => DateTime.to_unix(expires_at)}

    encoded_header = header |> Jason.encode!() |> Base.url_encode64(padding: false)
    encoded_payload = payload |> Jason.encode!() |> Base.url_encode64(padding: false)

    encoded_header <> "." <> encoded_payload <> ".signature"
  end
end
