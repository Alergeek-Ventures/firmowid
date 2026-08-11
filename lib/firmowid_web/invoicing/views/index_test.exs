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
  alias Firmowid.Ash.Finances.Requisition
  alias Firmowid.Ash.Finances.Transaction
  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Scope
  alias FirmowidWeb.Core.Endpoint
  alias Phoenix.Socket.Broadcast

  describe "requisition status PubSub notifications" do
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
          tenant: user.organization_id,
          actor: user
        )
        |> Ash.update(tenant: user.organization_id, actor: user)

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
          tenant: user.organization_id,
          actor: user
        )
        |> Ash.update(tenant: user.organization_id, actor: user)

      # Give PubSub a moment to deliver
      Process.sleep(50)

      # Verify LiveView is still alive and responsive
      assert render(view) =~ "Fakturowanie"
    end
  end

  describe "skip invoicing from list" do
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

      Process.sleep(10_100)

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
        CostInvoice.read!(
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
               CostInvoice.read!(
                 %{date_from: ~D[2026-04-01], date_to: ~D[2026-04-30], date_field: :issue_date},
                 scope: scope_for(user)
               )
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
        CostInvoice.read!(
          %{date_from: ~D[2026-04-01], date_to: ~D[2026-04-30], date_field: :issue_date},
          scope: scope_for(user)
        )

      assert length(invoices) == 1
    end
  end

  defp create_requisition(user, requisition_id) do
    Requisition
    |> Ash.Changeset.for_create(:persist, %{id: requisition_id},
      tenant: user.organization_id,
      actor: user,
      authorize?: false
    )
    |> Ash.create(tenant: user.organization_id, actor: user, authorize?: false)
  end

  defp sales_invoice_fixture!(user, invoice_number) do
    {:ok, invoice} =
      SalesInvoice.create(
        %{
          invoice_number: invoice_number,
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
        tenant: user.organization_id,
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
      organization_id: user.organization_id,
      skip_invoicing: false
    })
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
      organization_id: user.organization_id,
      skip_invoicing: false
    })
  end

  defp scope_for(user) do
    %Scope{actor: user, tenant: user.organization_id}
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
    CostInvoice.read!(
      %{date_from: ~D[2026-04-01], date_to: ~D[2026-04-30], date_field: :issue_date},
      scope: scope_for(user)
    )
  end

  defp subscribe_to_upload_notifications(user) do
    Endpoint.subscribe("blob:updated:#{user.organization_id}")
    Endpoint.subscribe("cost_invoice:created:#{user.organization_id}")
  end

  defp assert_cost_invoice_created(user) do
    assert_receive %Broadcast{
                     topic: "cost_invoice:created:" <> organization_id,
                     payload: %{resource: CostInvoice}
                   },
                   5_000

    assert organization_id == user.organization_id
  end

  defp assert_cost_invoice_blob_failed(user) do
    assert_receive %Broadcast{
                     topic: "blob:updated:" <> organization_id,
                     payload: %{resource: Blob, data: %{processing_state: :failed}}
                   },
                   5_000

    assert organization_id == user.organization_id
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
