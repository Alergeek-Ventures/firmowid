# credo:disable-for-this-file ExDNA.Credo
defmodule FirmowidWeb.Invoicing.SalesInvoices.Views.ShowTest do
  @moduledoc false
  use FirmowidWeb.ConnCase

  import Firmowid.AccountsFixtures
  import Firmowid.FinancesFixtures
  import Phoenix.LiveViewTest

  alias Firmowid.Ash.Finances
  alias Firmowid.Ash.Finances.Transaction
  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Invoicing.SalesInvoiceItem
  alias Firmowid.Ash.Ksef.Credential
  alias Firmowid.Ash.Ksef.KsefTestHelpers
  alias Firmowid.Ash.Ksef.Workers.SubmissionWorker
  alias Firmowid.Ash.Scope
  alias Firmowid.Repo
  alias Firmowid.Test.Support.InvoicingCopyAssertions
  alias FirmowidWeb.Invoicing.Utilities.Navigation

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

  test "shows flash when transaction connect fails", %{conn: conn} do
    admin = admin_fixture()
    invoice = sales_invoice_fixture!(admin)
    transaction = matching_transaction_fixture!(admin, invoice)
    conn = log_in_user(conn, admin)

    {:ok, view, _html} = live(conn, ~p"/sprzedazowe/#{invoice.id}")

    failed_html =
      view
      |> element("button[phx-click='connect']")
      |> render_click(%{"transaction_id" => Ash.UUID.generate()})

    assert failed_html =~ "Nie udało się połączyć transakcji"

    reloaded_invoice =
      Invoicing.get_sales_invoice!(invoice.id,
        load: [:transactions],
        scope: scope_for(admin)
      )

    assert reloaded_invoice.transactions == []
    assert transaction.id
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

  test "preserves transaction return context for back and edit navigation", %{conn: conn} do
    admin = admin_fixture()
    invoice = sales_invoice_fixture!(admin)
    conn = log_in_user(conn, admin)

    origin_return_to =
      Navigation.return_to_path("/fakturowanie?miesiac=2026-01-15&filtr=faktury&widok=lista")

    transaction_return_to = Navigation.transaction_show_path("tx-123", origin_return_to)

    {:ok, _view, html} =
      live(conn, Navigation.sales_invoice_show_path(invoice, transaction_return_to))

    assert html =~ ~s(href="#{transaction_return_to}")

    assert html =~
             ~s(href="#{Navigation.sales_invoice_edit_path(invoice, transaction_return_to)}")
  end

  test "does not expose an active edit control while KSeF submission is in progress", %{
    conn: conn
  } do
    admin = admin_fixture()
    invoice = sales_invoice_fixture!(admin)

    {:ok, _job} =
      %{
        "action" => "submit",
        "organization_id" => admin.organization_id,
        "sales_invoice_id" => invoice.id
      }
      |> SubmissionWorker.new(scheduled_at: DateTime.shift(DateTime.utc_now(), hour: 1))
      |> Repo.insert(prefix: "oban")

    conn = log_in_user(conn, admin)

    {:ok, _view, html} = live(conn, ~p"/sprzedazowe/#{invoice.id}")

    assert html =~ ~s(id="edit-invoice-button")
    assert html =~ ~s(disabled)
    refute html =~ ~s(id="edit-invoice-link")
    refute html =~ ~s(href="/sprzedazowe/#{invoice.id}/edytuj")
  end

  test "does not expose an active edit control for a locked invoice without a KSeF number", %{
    conn: conn
  } do
    admin = admin_fixture()
    invoice = sales_invoice_fixture!(admin)
    Ash.Seed.update!(invoice, %{locked_at: DateTime.utc_now()})

    conn = log_in_user(conn, admin)

    {:ok, _view, html} = live(conn, ~p"/sprzedazowe/#{invoice.id}")

    assert html =~ ~s(id="edit-invoice-button")
    assert html =~ ~s(disabled)
    refute html =~ ~s(id="edit-invoice-link")
    refute html =~ ~s(href="/sprzedazowe/#{invoice.id}/edytuj")
  end

  test "copy link targets the effective snapshot and copied draft matches latest correction", %{
    conn: conn
  } do
    admin = admin_fixture()
    scope = scope_for(admin)

    {:ok, default_eur_account} =
      Finances.create_manual_bank_account(
        %{
          iban: "DE99120300000000909090909090",
          name: "EUR default",
          currency: "EUR",
          is_default: true
        },
        scope: scope
      )

    original_invoice = sales_invoice_fixture!(admin)

    correction =
      Ash.Seed.seed!(SalesInvoice, %{
        invoice_number: "KOR/#{System.unique_integer([:positive])}",
        issue_date: ~D[2026-01-12],
        sale_date: ~D[2026-01-12],
        due_date: ~D[2026-01-20],
        payment_method: :card,
        invoice_type: :foreign,
        currency: "EUR",
        seller_nip: original_invoice.seller_nip,
        seller_display_name: original_invoice.seller_display_name,
        seller_address: original_invoice.seller_address,
        seller_account_number: "DE00111111111111111111",
        buyer_type: :company,
        buyer_id: "DE987654321",
        buyer_full_name: "Corrected Buyer GmbH",
        buyer_display_name: "Corrected Buyer Display",
        buyer_address: "Corrected Buyer address",
        buyer_country: "DE",
        buyer_email: "corrected@example.com",
        buyer_phone: "+49 999 999 999",
        buyer_description: "Corrected description",
        invoice_note: "Corrected invoice note",
        internal_note: "Corrected internal note",
        corrected_invoice_id: original_invoice.id,
        organization_id: admin.organization_id,
        is_reverse_charge: false,
        ksef_invoice_kind: :kor
      })

    Ash.Seed.seed!(SalesInvoiceItem, %{
      organization_id: admin.organization_id,
      sales_invoice_id: correction.id,
      index: 0,
      name: "Corrected line",
      quantity: Decimal.new("4"),
      unit: "szt.",
      unit_price: Decimal.new("50.00"),
      vat_rate: "23"
    })

    correction = Ash.load!(correction, [:sales_invoice_items], scope: scope)

    conn = log_in_user(conn, admin)

    {:ok, _show_view, html} = live(conn, ~p"/sprzedazowe/#{original_invoice.id}")

    copy_path = Navigation.sales_invoice_creator_path(%{skopiuj: correction.id})
    assert html =~ ~s(href="#{copy_path}")

    {:ok, _copy_view, _copy_html} = live(conn, copy_path)

    copied_draft =
      scope
      |> then(&Invoicing.list_wizard_drafts!(scope: &1))
      |> List.first()
      |> Ash.load!([:items], scope: scope)

    assert InvoicingCopyAssertions.assert_preserved_fields!(correction, copied_draft)
    assert InvoicingCopyAssertions.assert_cleared_dates!(copied_draft)

    assert InvoicingCopyAssertions.assert_derived_seller_account!(
             copied_draft,
             default_eur_account.iban
           )

    assert InvoicingCopyAssertions.assert_line_items_match!(
             correction.sales_invoice_items,
             copied_draft.items
           )
  end

  describe "cancellation" do
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

    test "submits the cancellation correction and navigates to its summary", %{conn: conn} do
      admin = admin_fixture()
      seed_ksef_submission_state!(admin.organization_id)
      invoice = sales_invoice_fixture!(admin)

      Ash.Seed.update!(invoice, %{
        ksef_number: "KSEF-ORIGINAL",
        ksef_invoice_checksum: "original-hash",
        locked_at: DateTime.utc_now()
      })

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
              "ksefNumber" => "KSEF-CANCELLATION",
              "acquisitionDate" => "2026-01-10T12:00:00Z",
              "invoiceHash" => "cancellation-hash"
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
      {:ok, view, html} = live(conn, ~p"/sprzedazowe/#{invoice.id}")
      assert html =~ "Anuluj fakturę"

      view
      |> element("#cancel-invoice-modal button", "Anuluj fakturę")
      |> render_click()

      cancelled_invoice =
        Invoicing.get_sales_invoice!(invoice.id,
          load: [:corrections],
          scope: scope_for(admin)
        )

      correction = List.first(cancelled_invoice.corrections)
      assert correction.ksef_number == "KSEF-CANCELLATION"
      assert correction.ksef_invoice_checksum == "cancellation-hash"
      assert_redirect(view, Navigation.sales_invoice_summary_path(correction))
    end
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
      amount: Money.new!(invoice.currency, invoice.gross_value),
      booking_date: invoice.issue_date,
      value_date: invoice.issue_date,
      remittance_information_unstructured: "Payment January",
      bank_account_id: bank_account_fixture!(admin).id,
      organization_id: admin.organization_id
    })
  end

  defp scope_for(user) do
    %Scope{actor: user, tenant: user.organization_id}
  end

  defp seed_ksef_submission_state!(organization_id) do
    Ash.Seed.seed!(Credential, %{
      organization_id: organization_id,
      status: :working,
      auth_type: :token,
      credentials: "token-#{System.unique_integer([:positive])}"
    })

    Cachex.put(:ksef, {:access_token, organization_id}, KsefTestHelpers.jwt(300), expire: to_timeout(minute: 5))

    private_key = X509.PrivateKey.new_rsa(2048)
    certificate = X509.Certificate.self_signed(private_key, "/CN=KSeF Test")

    Cachex.put(:ksef, {:public_key, "SymmetricKeyEncryption"}, certificate)
  end
end
