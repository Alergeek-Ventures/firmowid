defmodule FirmowidWeb.Invoicing.Views.IndexTest do
  @moduledoc """
  Tests for the Invoicing Index LiveView PubSub notifications.

  Uses Ash integration test approach - creates actual requisitions,
  performs state transitions, and lets Ash.Notifier.PubSub broadcast
  naturally to the LiveView.
  """
  use FirmowidWeb.ConnCase

  import Firmowid.AccountsFixtures
  import Firmowid.FinancesFixtures
  import Firmowid.Test.Support.OpenAIEnrichmentTestHelpers
  import Phoenix.LiveViewTest

  alias Firmowid.Ash.Blobs.Blob
  alias Firmowid.Ash.Finances
  alias Firmowid.Ash.Finances.BankAccount
  alias Firmowid.Ash.Finances.Requisition
  alias Firmowid.Ash.Finances.Transaction
  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Invoicing.SkippedKsefSalesInvoice
  alias Firmowid.Ash.Scope
  alias Firmowid.InvoicingFixtures
  alias FirmowidWeb.Core.Endpoint
  alias Phoenix.Socket.Broadcast

  test "payment and skipping a corrected cost invoice use only the original", %{conn: conn} do
    user = admin_fixture()
    scope = scope_for(user)
    conn = log_in_user(conn, user)
    invoice = corrected_cost_invoice_fixture!(user)

    {:ok, dashboard, _html} = live(conn, ~p"/fakturowanie?miesiac=2026-01-01")

    assert has_element?(
             dashboard,
             "a[href='/kosztowe/#{invoice.id}']",
             invoice.invoice_identifier
           )

    refute has_element?(dashboard, "a", "KOR-PAYMENT-METHOD")

    first_payment =
      transaction_fixture!(user, invoice.seller, invoice.issue_date, "FIRST-INSTALLMENT")

    second_payment =
      transaction_fixture!(user, invoice.seller, invoice.issue_date, "SECOND-INSTALLMENT")

    Invoicing.connect_cost_invoice_transactions!(invoice, [first_payment.id, second_payment.id], scope: scope)

    paid = Invoicing.get_cost_invoice!(invoice.id, load: [:transactions], scope: scope)

    assert MapSet.new(paid.transactions, & &1.id) ==
             MapSet.new([first_payment.id, second_payment.id])

    {:ok, paid_dashboard, _html} = live(conn, ~p"/fakturowanie?miesiac=2026-01-01")
    assert has_element?(paid_dashboard, "p", "Brak nieopłaconych faktur.")

    {:ok, details, _html} = live(conn, ~p"/kosztowe/#{invoice.id}")
    details |> element("#invoice-show button[phx-click='disconnect']") |> render_click()
    details |> element("button", "Pomiń") |> render_click()
    assert has_element?(details, "div", "Transakcja pominięta")

    assert Invoicing.get_cost_invoice!(invoice.id, scope: scope).skip_invoicing

    {:ok, skipped_dashboard, _html} = live(conn, ~p"/fakturowanie?miesiac=2026-01-01")
    assert has_element?(skipped_dashboard, "p", "Brak nieopłaconych faktur.")
  end

  describe "invoicing access" do
    test "redirects employees to time tracking", %{conn: conn} do
      user = user_fixture(%{role: :employee})

      assert {:error, {:redirect, %{to: "/czasosledz"}}} =
               conn |> log_in_user(user) |> live(~p"/fakturowanie")
    end

    for role <- [:invoicing, :accountant, :admin] do
      @role role

      test "#{role} can view only their organization's invoices", %{conn: conn} do
        user = user_fixture(%{role: @role})
        other_user = admin_fixture()
        invoice = sales_invoice_fixture!(user, "SYNTHETIC-OWN")
        other_invoice = sales_invoice_fixture!(other_user, "SYNTHETIC-OTHER")

        {:ok, view, _html} =
          conn
          |> log_in_user(user)
          |> live(~p"/fakturowanie?miesiac=2026-01-01&filtr=faktury&widok=lista")

        assert has_element?(
                 view,
                 "#invoicing-entries tr[id='#{invoice.id}-row']",
                 "Buyer Company"
               )

        refute has_element?(view, "#invoicing-entries tr[id='#{other_invoice.id}-row']")

        if @role == :invoicing do
          refute has_element?(view, "#upload-form")
          refute has_element?(view, "#sales-invoice-link")
        else
          assert has_element?(view, "#upload-form")
          assert has_element?(view, "#sales-invoice-link")
        end
      end
    end
  end

  describe "requisition status PubSub notifications" do
    test "shows an expired bank in suggestions and never exposes another organization's account",
         %{conn: conn} do
      user = admin_fixture()
      other_user = admin_fixture()

      requisition =
        Ash.Seed.seed!(Requisition, %{id: Ecto.UUID.generate(), status: :accepted}, tenant: user.member.organization_id)

      account =
        bank_account_fixture!(user, %{
          requisition_id: requisition.id,
          gocardless_id: "synthetic-bank-account",
          institution_id: "ING_PL_INGBPLPW",
          institution_name: "Synthetic Bank"
        })

      other_requisition =
        Ash.Seed.seed!(Requisition, %{id: Ecto.UUID.generate(), status: :expired},
          tenant: other_user.member.organization_id
        )

      other_account =
        bank_account_fixture!(other_user, %{
          requisition_id: other_requisition.id,
          gocardless_id: "synthetic-other-account"
        })

      {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/fakturowanie")
      assert has_element?(view, "#dashboard-attention h2", "Warte uwagi")
      refute has_element?(view, "#dashboard-attention .bg-red-200")

      assert has_element?(
               view,
               "#bank-connection-alert-#{account.id}",
               "Transakcje nie są aktualizowane."
             )

      assert {:ok, _} =
               BankAccount.sync_from_gocardless(account,
                 actor: user,
                 tenant: user.member.organization_id
               )

      refute has_element?(view, "#bank-connection-alert-#{account.id}")

      assert {:ok, _} =
               Requisition.expire(requisition, actor: user, tenant: user.member.organization_id)

      assert has_element?(
               view,
               "#bank-connection-alert-#{account.id}",
               "Połączenie z Synthetic Bank wygasło"
             )

      assert has_element?(view, "#dashboard-attention .bg-red-200")

      assert has_element?(
               view,
               "#dashboard-attention #bank-connection-alert-#{account.id} [data-bank='ING']"
             )

      assert has_element?(
               view,
               "#dashboard-attention a[href='/ustawienia/firma#konto-bankowe-#{account.id}']",
               "Połączenie z Synthetic Bank wygasło"
             )

      refute has_element?(view, "#bank-connection-alert-#{other_account.id}")

      assert {:ok, _} =
               BankAccount.mark_sync_failed(account,
                 actor: user,
                 tenant: user.member.organization_id
               )

      renewed =
        Ash.Seed.seed!(Requisition, %{id: Ecto.UUID.generate(), status: :accepted}, tenant: user.member.organization_id)

      assert {:ok, reconnected} =
               account
               |> Map.take([:iban, :currency, :name, :institution_name])
               |> Map.merge(%{
                 gocardless_id: "synthetic-renewed-account",
                 requisition_id: renewed.id
               })
               |> Finances.sync_bank_account(actor: user, tenant: user.member.organization_id)

      assert reconnected.id == account.id

      {:ok, renewed_view, _html} = conn |> log_in_user(user) |> live(~p"/fakturowanie")
      assert has_element?(renewed_view, "#bank-connection-alert-#{account.id}")

      refute has_element?(
               renewed_view,
               "#bank-connection-alert-#{account.id}",
               "Połączenie z Synthetic Bank wygasło"
             )

      assert {:ok, _} =
               BankAccount.sync_from_gocardless(reconnected,
                 actor: user,
                 tenant: user.member.organization_id
               )

      refute has_element?(renewed_view, "#bank-connection-alert-#{account.id}")
      refute has_element?(renewed_view, "#dashboard-attention .bg-red-200")
    end

    test "shows one concise warning per bank using the earliest known synchronization gap", %{
      conn: conn,
      user: user
    } do
      requisition =
        Ash.Seed.seed!(Requisition, %{id: Ecto.UUID.generate(), status: :expired}, tenant: user.member.organization_id)

      for {currency, synced_at} <- [
            {"PLN", ~U[2026-01-12 10:00:00Z]},
            {"EUR", ~U[2026-01-15 10:00:00Z]}
          ] do
        account =
          bank_account_fixture!(user, %{
            requisition_id: requisition.id,
            gocardless_id: "synthetic-grouped-#{currency}",
            institution_id: "ING_PL_INGBPLPW",
            institution_name: "Synthetic Bank",
            currency: currency
          })

        Ash.Seed.seed!(
          Firmowid.Ash.Events.Event,
          %{
            organization_id: user.member.organization_id,
            record_id: account.id,
            resource: BankAccount,
            action: :sync_from_gocardless,
            action_type: :update,
            occurred_at: synced_at,
            metadata: %{},
            data: %{},
            changed_attributes: %{},
            version: 1
          },
          tenant: user.member.organization_id
        )
      end

      {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/fakturowanie")
      warning = view |> element("#dashboard-attention [id^='bank-connection-alert-']") |> render()
      assert warning =~ "Połączenie z Synthetic Bank wygasło"
      assert warning =~ "Od 12.01.2026 transakcje nie są synchronizowane"
    end

    test "keeps skipped KSeF invoices inside the attention column and scoped to the organization",
         %{conn: conn, user: user} do
      other_user = admin_fixture()

      attributes = %{
        issue_date: ~D[2026-10-01],
        buyer_name: "Synthetic buyer",
        gross_total: Decimal.new("123.00"),
        currency: "PLN",
        reason: "synthetic unsupported invoice",
        ksef_permanent_storage_date: ~N[2026-10-01 10:00:00]
      }

      for {owner, suffix} <- [{user, "own"}, {user, "second"}, {other_user, "other"}] do
        Ash.Seed.seed!(
          SkippedKsefSalesInvoice,
          Map.merge(attributes, %{
            ksef_number: "synthetic-skipped-#{suffix}",
            invoice_number: "SYNTHETIC-#{suffix}"
          }),
          tenant: owner.member.organization_id
        )
      end

      {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/fakturowanie")

      assert has_element?(
               view,
               "#dashboard-attention #skipped-ksef-sales-invoices li",
               "SYNTHETIC-own"
             )

      refute has_element?(view, "#skipped-ksef-sales-invoices li", "SYNTHETIC-other")
      assert has_element?(view, "#skipped-ksef-sales-invoices li", "SYNTHETIC-second")

      Ash.Seed.seed!(
        SkippedKsefSalesInvoice,
        Map.merge(attributes, %{
          ksef_number: "synthetic-skipped-third",
          invoice_number: "SYNTHETIC-third"
        }),
        tenant: user.member.organization_id
      )

      {:ok, summary_view, _html} = conn |> log_in_user(user) |> live(~p"/fakturowanie")

      assert has_element?(
               summary_view,
               "#skipped-ksef-sales-invoices p",
               "Nie udało się zsynchronizować 3 faktur."
             )

      refute has_element?(summary_view, "#skipped-ksef-sales-invoices li")

      assert has_element?(
               summary_view,
               "#skipped-ksef-sales-invoices p",
               "Wykryliśmy problem z importem."
             )

      {:ok, list_view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/fakturowanie?filtr=nieprzypisane&widok=lista")

      refute has_element?(list_view, "#dashboard-attention")
      refute has_element?(list_view, "#skipped-ksef-sales-invoices")
    end

    setup do
      user = admin_fixture()

      # Stub GoCardless API calls
      Req.Test.stub(:bank_data_requisition, fn conn ->
        Req.Test.json(conn, %{
          "id" => "test-req-id",
          "status" => "LN",
          "accounts" => ["account-123"]
        })
      end)

      Req.Test.stub(:bank_data_account, fn conn ->
        Req.Test.json(conn, %{
          "id" => "account-123",
          "iban" => "GL123456789",
          "name" => "Test Account",
          "currency" => "EUR",
          "ownerName" => "Test Owner"
        })
      end)

      Req.Test.stub(:bank_data_institution, fn conn ->
        Req.Test.json(conn, %{
          "id" => "test-institution",
          "name" => "Test Bank",
          "bic" => "TESTBIC"
        })
      end)

      Req.Test.stub(:bank_data_transactions, fn conn ->
        Req.Test.json(conn, %{
          "transactions" => %{"booked" => []}
        })
      end)

      %{user: user}
    end

    test "handles accept notification without crashing", %{conn: conn, user: user} do
      requisition_id = Ecto.UUID.generate()

      {:ok, requisition} = create_requisition(user, requisition_id)

      # Mount the LiveView (subscribes to PubSub topics)
      {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/fakturowanie")

      # Accept the requisition - triggers Ash.Notifier.PubSub broadcast
      # This will call GoCardless API (stubbed above) and broadcast :linked
      {:ok, _accepted} =
        requisition
        |> Ash.Changeset.for_update(:accept, %{},
          tenant: user.member.organization_id,
          actor: user
        )
        |> Ash.update(tenant: user.member.organization_id, actor: user)

      # Give PubSub a moment to deliver
      Process.sleep(50)

      # Verify LiveView is still alive and responsive
      assert render(view) =~ "Fakturowanie"
    end

    test "handles reject notification without crashing", %{conn: conn, user: user} do
      requisition_id = Ecto.UUID.generate()

      {:ok, requisition} = create_requisition(user, requisition_id)

      # Mount the LiveView
      {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/fakturowanie")

      # Reject the requisition - triggers Ash.Notifier.PubSub broadcast
      {:ok, _rejected} =
        requisition
        |> Ash.Changeset.for_update(:reject, %{},
          tenant: user.member.organization_id,
          actor: user
        )
        |> Ash.update(tenant: user.member.organization_id, actor: user)

      # Give PubSub a moment to deliver
      Process.sleep(50)

      # Verify LiveView is still alive and responsive
      assert render(view) =~ "Fakturowanie"
    end
  end

  describe "skip invoicing from list" do
    test "updates a transaction status immediately when skipping and restoring", %{conn: conn} do
      user = admin_fixture()
      transaction = transaction_fixture!(user, "Single Party", ~D[2026-01-10], "SINGLE")

      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/fakturowanie?miesiac=2026-01-01&filtr=wszystkie&widok=lista")

      assert has_element?(view, "##{transaction.id}-button", "Pomiń")

      view |> element("##{transaction.id}-button", "Pomiń") |> render_click()

      refute has_element?(view, "##{transaction.id}-button", "Pomiń")
      assert has_element?(view, "##{transaction.id}-button .hero-arrow-uturn-left-micro")
      assert Finances.get_transaction!(transaction.id, scope: scope_for(user)).skip_invoicing

      view |> element("##{transaction.id}-button") |> render_click()

      assert has_element?(view, "##{transaction.id}-button", "Pomiń")
      refute Finances.get_transaction!(transaction.id, scope: scope_for(user)).skip_invoicing
    end

    test "skips a single invoice from unmatched list", %{conn: conn} do
      user = admin_fixture()
      invoice = sales_invoice_fixture!(user, "FV-LIST-SINGLE")

      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/fakturowanie?miesiac=2026-01-01&filtr=nieprzypisane&widok=lista")

      updated_html =
        view
        |> element("##{invoice.id}-button")
        |> render_click()

      refute updated_html =~ "Pomiń"

      skipped_invoice = Invoicing.get_sales_invoice!(invoice.id, scope: scope_for(user))
      assert skipped_invoice.skip_invoicing
    end

    test "skips a group of transactions from unmatched list", %{conn: conn} do
      user = admin_fixture()
      tx1 = transaction_fixture!(user, "Grouped Party", ~D[2026-01-10], "PAYMENT-A")
      tx2 = transaction_fixture!(user, "Grouped Party", ~D[2026-01-10], "PAYMENT-B")

      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/fakturowanie?miesiac=2026-01-01&filtr=nieprzypisane&widok=lista")

      html = render(view)

      [group_button_id] =
        Regex.run(
          ~r/id="([^"]+-button)"[^>]*phx-click="[^"]*toggle-skip-invoicing-group/s,
          html,
          capture: :all_but_first
        )

      assert html =~ "Grouped Party"
      assert html =~ "2 transakcje"

      _updated_html =
        view
        |> element("##{group_button_id}")
        |> render_click()

      updated_html = render(view)

      assert updated_html =~ "Grouped Party"
      assert updated_html =~ "2 transakcje"
      refute updated_html =~ ~s(#{group_button_id}">Pomiń)

      skipped_tx1 = Finances.get_transaction!(tx1.id, scope: scope_for(user))
      skipped_tx2 = Finances.get_transaction!(tx2.id, scope: scope_for(user))

      assert skipped_tx1.skip_invoicing
      assert skipped_tx2.skip_invoicing

      for transaction <- [tx1, tx2] do
        refute has_element?(view, "##{transaction.id}-button", "Pomiń")
        assert has_element?(view, "##{transaction.id}-button .hero-arrow-uturn-left-micro")
      end

      # Exercise the refresh without waiting for the animation delay. Timer
      # scheduling and cancellation are covered by PubSubDebounceTest.
      send(view.pid, {:debounced_refetch, :invoicing_entries})

      html_after_debounce = render(view)

      refute html_after_debounce =~ "Grouped Party"
      refute html_after_debounce =~ "2 transakcje"
    end

    test "renders distinct income and cost group ids for the same party", %{conn: conn} do
      user = admin_fixture()

      transaction_fixture!(user, "Shared Party", ~D[2026-05-10], "COST-A")
      transaction_fixture!(user, "Shared Party", ~D[2026-05-10], "COST-B")
      income_transaction_fixture!(user, "Shared Party", ~D[2026-05-10], "INCOME-A")
      income_transaction_fixture!(user, "Shared Party", ~D[2026-05-10], "INCOME-B")

      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/fakturowanie?miesiac=2026-05-01&filtr=nieprzypisane&widok=lista")

      html = render(view)

      group_row_ids =
        ~r/<tr id="(group-[^"]+)-row" class="cursor-pointer duration-200"/
        |> Regex.scan(html,
          capture: :all_but_first
        )
        |> List.flatten()

      assert length(group_row_ids) == 2
      assert Enum.uniq(group_row_ids) == group_row_ids
      assert Enum.any?(group_row_ids, &String.starts_with?(&1, "group-cost-"))
      assert Enum.any?(group_row_ids, &String.starts_with?(&1, "group-income-"))
    end
  end

  describe "cost invoice upload with mocked Reducto" do
    setup do
      previous_openai = Application.get_env(:firmowid, :openai_enrichment)
      previous_openai_ex = Application.get_env(:firmowid, :openai_ex)
      previous_extract_result = Application.get_env(:firmowid, :reducto_extract_result)
      previous_reducto_config = Application.get_env(:firmowid, :reducto_api_client)
      {:ok, openai_ex_base_url} = start_openai_ex_http_stub()
      {:ok, reducto_base_url} = start_reducto_http_stub()

      Application.put_env(
        :firmowid,
        :reducto_api_client,
        base_url: reducto_base_url
      )

      Application.put_env(
        :firmowid,
        :openai_enrichment,
        base_url: openai_ex_base_url
      )

      Application.put_env(:firmowid, :openai_ex, base_url: openai_ex_base_url)

      on_exit(fn ->
        restore_env(:openai_enrichment, previous_openai)
        restore_env(:openai_ex, previous_openai_ex)
        restore_env(:reducto_extract_result, previous_extract_result)
        restore_env(:reducto_api_client, previous_reducto_config)
      end)

      user = admin_fixture()

      %{user: user}
    end

    test "uploads a cost invoice and shows it in the list", %{conn: conn, user: user} do
      put_reducto_extract_result({:ok, cost_invoice_document()})

      {:ok, view, html} =
        conn
        |> log_in_user(user)
        |> live(~p"/fakturowanie?miesiac=2026-04-01&filtr=faktury&widok=lista")

      assert html =~ "Brak transakcji i dokumentów dla wybranej daty"
      subscribe_to_upload_notifications(user)

      upload_invoice(view, "upload-success.png")
      assert_cost_invoice_created(user)

      rendered = render(view)

      assert rendered =~ "Faktura załadowana"
      assert rendered =~ "Upload Supplier Sp. z o.o."
      assert rendered =~ "Zakup testowy"

      [invoice] =
        CostInvoice.list!(
          %{date_from: ~D[2026-04-01], date_to: ~D[2026-04-30], date_field: :issue_date},
          scope: scope_for(user)
        )

      assert rendered =~ ~s(href="/kosztowe/#{invoice.id}")
      assert invoice.invoice_identifier == "FV/UPLOAD/001"
      assert invoice.seller == "Upload Supplier Sp. z o.o."
    end

    test "shows an invalid document toast when Reducto rejects the upload", %{
      conn: conn,
      user: user
    } do
      put_reducto_extract_result({:ok, %{"document_type" => "invalid"}})

      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/fakturowanie?miesiac=2026-04-01&filtr=faktury&widok=lista")

      subscribe_to_upload_notifications(user)
      upload_invoice(view, "upload-invalid.png")
      assert_cost_invoice_blob_failed(user)

      rendered = render(view)

      assert rendered =~ "Nieprawidłowy dokument"
      assert rendered =~ "Plik nie zawiera danych wymaganych dla faktury kosztowej."

      assert [] ==
               CostInvoice.list!(
                 %{date_from: ~D[2026-04-01], date_to: ~D[2026-04-30], date_field: :issue_date},
                 scope: scope_for(user)
               )
    end

    test "shows an invalid document toast when Reducto omits required invoice data", %{
      conn: conn,
      user: user
    } do
      put_reducto_extract_result({:ok, Map.delete(cost_invoice_document(), "total_amount")})

      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/fakturowanie?miesiac=2026-04-01&filtr=faktury&widok=lista")

      subscribe_to_upload_notifications(user)
      upload_invoice(view, "upload-missing-data.png")
      assert_cost_invoice_blob_failed(user)

      rendered = render(view)

      assert rendered =~ "Nieprawidłowy dokument"
      assert rendered =~ "Plik nie zawiera danych wymaganych dla faktury kosztowej."
      assert cost_invoices_for_upload_month(user) == []
    end

    test "shows an invalid document toast when Reducto cannot process the file", %{
      conn: conn,
      user: user
    } do
      put_reducto_extract_result(
        {:http_error, 415,
         %{
           "error" => %{
             "code" => 415,
             "message" => "The document could not be processed. Verify the file is valid or try re-exporting it.",
             "name" => "DOCUMENT_CORRUPT"
           }
         }}
      )

      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/fakturowanie?miesiac=2026-04-01&filtr=faktury&widok=lista")

      subscribe_to_upload_notifications(user)
      upload_invoice(view, "upload-corrupt.svg")
      assert_cost_invoice_blob_failed(user)

      rendered = render(view)

      assert rendered =~ "Nieprawidłowy dokument"
      assert rendered =~ "Plik nie zawiera danych wymaganych dla faktury kosztowej."
      refute rendered =~ "Wystąpił problem po naszej stronie"
    end

    test "shows a processing error toast when Reducto fails unexpectedly", %{
      conn: conn,
      user: user
    } do
      put_reducto_extract_result({:http_error, 401, %{"error" => "Invalid API key"}})

      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/fakturowanie?miesiac=2026-04-01&filtr=faktury&widok=lista")

      subscribe_to_upload_notifications(user)
      upload_invoice(view, "upload-reducto-error.png")
      assert_cost_invoice_blob_failed(user)

      rendered = render(view)
      assert rendered =~ "Nie udało się wgrać pliku"
      assert rendered =~ "Nie udało się przetworzyć pliku."
      refute rendered =~ "Nieprawidłowy dokument"
      assert cost_invoices_for_upload_month(user) == []
    end

    test "shows a duplicate toast when uploading the same cost invoice twice", %{
      conn: conn,
      user: user
    } do
      put_reducto_extract_result({:ok, cost_invoice_document()})

      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/fakturowanie?miesiac=2026-04-01&filtr=faktury&widok=lista")

      subscribe_to_upload_notifications(user)
      upload_invoice(view, "upload-success.png")
      assert_cost_invoice_created(user)

      first_invoice = cost_invoices_for_upload_month(user)

      assert length(first_invoice) == 1

      upload_invoice(view, "upload-success-duplicate.png")

      rendered = render(view)

      assert rendered =~ "Ta faktura jest już w systemie"
      assert rendered =~ "Wyświetl"

      invoices =
        CostInvoice.list!(
          %{date_from: ~D[2026-04-01], date_to: ~D[2026-04-30], date_field: :issue_date},
          scope: scope_for(user)
        )

      assert length(invoices) == 1
    end
  end

  defp create_requisition(user, requisition_id) do
    %{id: requisition_id}
    |> Requisition.changeset_to_persist(
      tenant: user.member.organization_id,
      actor: user,
      authorize?: false
    )
    |> Ash.create(tenant: user.member.organization_id, actor: user, authorize?: false)
  end

  defp sales_invoice_fixture!(user, invoice_number) do
    {:ok, invoice} =
      InvoicingFixtures.seed_sales_invoice(
        %{
          invoice_number: invoice_number,
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
        tenant: user.member.organization_id,
        actor: user
      )

    invoice
  end

  defp transaction_fixture!(user, creditor_name, booking_date, suffix) do
    Ash.Seed.seed!(Transaction, %{
      transaction_id: "TX-#{suffix}",
      internal_transaction_id: "INT-#{suffix}",
      creditor_name: creditor_name,
      creditor_account: "PL02114020040000300201355387",
      debtor_name: "Bytecraft",
      debtor_account: "PL61109010140000071219812874",
      amount: Money.new!("EUR", Decimal.new("-50.00")),
      booking_date: booking_date,
      value_date: booking_date,
      remittance_information_unstructured: "#{suffix}",
      bank_account_id: bank_account_fixture!(user).id,
      organization_id: user.member.organization_id,
      skip_invoicing: false
    })
  end

  defp corrected_cost_invoice_fixture!(user) do
    blob =
      Ash.Seed.seed!(Blob, %{
        blob_path: "correction-regression/original.pdf",
        blob_checksum: String.duplicate("a", 64),
        original_filename: "original.pdf",
        organization_id: user.member.organization_id
      })

    attributes = %{
      seller: "Corrected Supplier",
      seller_display_name: "Corrected Supplier",
      sale_date: ~D[2026-01-10],
      issue_date: ~D[2026-01-10],
      due_date: ~D[2026-01-24],
      amount: Money.new!("EUR", "-100.00"),
      description: "Payment method correction",
      payment_method: :bank_transfer,
      organization_id: user.member.organization_id
    }

    invoice =
      Ash.Seed.seed!(
        CostInvoice,
        Map.merge(attributes, %{
          invoice_identifier: "ROOT-PAYMENT-METHOD",
          blob_id: blob.id,
          ksef_number: "KSEF-ROOT-PAYMENT-METHOD"
        })
      )

    Ash.Seed.seed!(
      CostInvoice,
      Map.merge(attributes, %{
        invoice_identifier: "KOR-PAYMENT-METHOD",
        invoice_type: :kor,
        ksef_number: "KSEF-KOR-PAYMENT-METHOD",
        original_invoice_ksef_number: invoice.ksef_number,
        ksef_permanent_storage_date: ~N[2026-01-11 12:00:00],
        amount: Money.new!("EUR", "0"),
        payment_method: :cash
      })
    )

    invoice
  end

  defp income_transaction_fixture!(user, debtor_name, booking_date, suffix) do
    Ash.Seed.seed!(Transaction, %{
      transaction_id: "TX-#{suffix}",
      internal_transaction_id: "INT-#{suffix}",
      creditor_name: "Bytecraft",
      creditor_account: "PL02114020040000300201355387",
      debtor_name: debtor_name,
      debtor_account: "PL61109010140000071219812874",
      amount: Money.new!("EUR", Decimal.new("50.00")),
      booking_date: booking_date,
      value_date: booking_date,
      remittance_information_unstructured: "#{suffix}",
      bank_account_id: bank_account_fixture!(user).id,
      organization_id: user.member.organization_id,
      skip_invoicing: false
    })
  end

  defp scope_for(user) do
    %Scope{actor: user, tenant: user.member.organization_id}
  end

  defp upload_invoice(view, filename) do
    upload_fixture = Path.expand("../../../test/fixtures/receipt.png", __DIR__)

    view
    |> file_input("#upload-form", :file, [
      %{name: filename, content: File.read!(upload_fixture), type: "image/png"}
    ])
    |> render_upload(filename)
  end

  defp put_reducto_extract_result(result) do
    Application.put_env(:firmowid, :reducto_extract_result, result)
  end

  defp cost_invoices_for_upload_month(user) do
    CostInvoice.list!(
      %{date_from: ~D[2026-04-01], date_to: ~D[2026-04-30], date_field: :issue_date},
      scope: scope_for(user)
    )
  end

  defp subscribe_to_upload_notifications(user) do
    Endpoint.subscribe("blob:updated:#{user.member.organization_id}")
    Endpoint.subscribe("cost_invoice:created:#{user.member.organization_id}")
  end

  defp assert_cost_invoice_created(user) do
    assert_receive %Broadcast{
                     topic: "cost_invoice:created:" <> organization_id,
                     payload: %{resource: CostInvoice}
                   },
                   5_000

    assert organization_id == user.member.organization_id
  end

  defp assert_cost_invoice_blob_failed(user) do
    assert_receive %Broadcast{
                     topic: "blob:updated:" <> organization_id,
                     payload: %{resource: Blob, data: %{processing_state: :failed}}
                   },
                   5_000

    assert organization_id == user.member.organization_id
  end

  defp cost_invoice_document do
    %{
      "document_type" => "cost_invoice",
      "sale_date" => "2026-04-10",
      "issue_date" => "2026-04-10",
      "due_date" => "2026-04-24",
      "seller" => "Upload Supplier Sp. z o.o.",
      "seller_nip" => "1234567890",
      "seller_address" => "Testowa 1, Kraków",
      "total_amount" => 123.45,
      "currency" => "EUR",
      "invoice_identifier" => "FV/UPLOAD/001",
      "account_number" => "PL61109010140000071219812874",
      "items_list" => [
        %{"name" => "Usługa testowa", "quantity" => 1, "price" => 123.45}
      ]
    }
  end

  defp restore_env(key, nil), do: Application.delete_env(:firmowid, key)
  defp restore_env(key, value), do: Application.put_env(:firmowid, key, value)
end
