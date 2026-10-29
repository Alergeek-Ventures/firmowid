defmodule Firmowid.Ksef.Workers.SubmissionWorkerTest do
  @moduledoc false
  use Firmowid.DataCase, async: false

  import Firmowid.AccountsFixtures
  import Firmowid.Ksef.KsefTestHelpers, only: [jwt: 1]

  alias Firmowid.Invoicing.SalesInvoice
  alias Firmowid.InvoicingFixtures
  alias Firmowid.Ksef.Workers.SessionWorker
  alias Firmowid.Ksef.Workers.SubmissionWorker
  alias Firmowid.Scope

  @moduletag capture_log: true

  setup do
    on_exit(fn -> Cachex.clear(:ksef) end)
  end

  test "returns a VAT invoice KSeF rejected to an unnumbered draft" do
    admin = admin_fixture()
    invoice = submitted_invoice!(admin, %{ksef_invoice_kind: :vat})

    reject_verification!(admin.member.organization_id)
    verify!(invoice)

    withdrawn = SalesInvoice.by_id!(invoice.id, scope: scope_for(admin))
    assert is_nil(withdrawn.invoice_number)
    assert is_nil(withdrawn.locked_at)
    assert is_nil(withdrawn.ksef_number)
  end

  test "deletes a correction KSeF rejected" do
    admin = admin_fixture()

    original =
      submitted_invoice!(admin, %{
        ksef_invoice_kind: :vat,
        ksef_number: "KSEF-ORIGINAL",
        locked_at: nil
      })

    correction =
      submitted_invoice!(admin, %{ksef_invoice_kind: :kor, corrected_invoice_id: original.id})

    reject_verification!(admin.member.organization_id)
    verify!(correction)

    assert {:ok, nil} =
             SalesInvoice.by_id(correction.id, scope: scope_for(admin), not_found_error?: false)
  end

  test "keeps an invoice KSeF is still processing after the polling limit and checks it hourly" do
    admin = admin_fixture()
    invoice = submitted_invoice!(admin, %{ksef_invoice_kind: :vat})

    InvoicingFixtures.accept_ksef_submissions!(admin.member.organization_id)

    Req.Test.stub(:ksef_api, fn conn ->
      Req.Test.json(conn, %{"status" => %{"code" => 150, "description" => "Processing"}})
    end)

    assert {:snooze, 3600} = verify!(invoice, meta: %{"snoozed" => 360})

    kept = SalesInvoice.by_id!(invoice.id, scope: scope_for(admin))
    assert kept.invoice_number == invoice.invoice_number
    assert kept.locked_at
  end

  test "keeps a numbered invoice locked when its status cannot be read on the last attempt" do
    admin = admin_fixture()
    invoice = submitted_invoice!(admin, %{ksef_invoice_kind: :vat})
    Cachex.put(:ksef, {:access_token, invoice.organization_id}, jwt(3600))
    Req.Test.stub(:ksef_api, fn conn -> Plug.Conn.send_resp(conn, 403, "unavailable") end)

    assert {:snooze, 3600} = verify!(invoice, attempt: 3)
    kept = SalesInvoice.by_id!(invoice.id, scope: scope_for(admin))
    assert kept.invoice_number == invoice.invoice_number
    assert kept.locked_at == invoice.locked_at
    assert kept.ksef_invoice_checksum == invoice.ksef_invoice_checksum
    assert kept.ksef_session_reference_number == invoice.ksef_session_reference_number
    assert kept.ksef_number == nil
  end

  test "reschedules verification after an expected renewal failure on the last attempt" do
    admin = admin_fixture()
    invoice = submitted_invoice!(admin, %{ksef_invoice_kind: :vat})
    Req.Test.stub(:ksef_api, fn conn -> Plug.Conn.send_resp(conn, 403, "unavailable") end)

    Oban.Testing.with_testing_mode(:manual, fn ->
      schedule_refresh_token!(invoice.organization_id)
      assert {:snooze, 3600} = verify!(invoice, attempt: 3)
      assert {:error, :forbidden} = verify!(invoice)
      assert {:ok, nil} = Cachex.get(:ksef, {:access_token, invoice.organization_id})

      assert_raise RuntimeError, ~r/KSeF session renewal failed/, fn ->
        SessionWorker.get_access_token!(invoice.organization_id)
      end
    end)

    kept = SalesInvoice.by_id!(invoice.id, scope: scope_for(admin))
    assert kept.invoice_number == invoice.invoice_number
    assert kept.locked_at == invoice.locked_at
    assert kept.ksef_invoice_checksum == invoice.ksef_invoice_checksum
  end

  test "keeps checking after refresh token expiry and schedules reauthentication" do
    admin = admin_fixture()
    invoice = submitted_invoice!(admin, %{ksef_invoice_kind: :vat})

    Oban.Testing.with_testing_mode(:manual, fn ->
      assert {:snooze, 3600} = verify!(invoice, attempt: 3)
      assert_enqueued(worker: SessionWorker, args: %{organization_id: invoice.organization_id})

      assert_raise RuntimeError, "Refresh token expired, re-authentication scheduled", fn ->
        SessionWorker.get_access_token!(invoice.organization_id)
      end
    end)

    kept = SalesInvoice.by_id!(invoice.id, scope: scope_for(admin))
    assert kept.locked_at == invoice.locked_at
    assert kept.invoice_number == invoice.invoice_number
  end

  test "unexpected renewal exceptions still bubble without changing the document" do
    admin = admin_fixture()
    invoice = submitted_invoice!(admin, %{ksef_invoice_kind: :vat})

    Req.Test.stub(:ksef_api, fn _conn -> raise "unexpected transport failure" end)

    Oban.Testing.with_testing_mode(:manual, fn ->
      schedule_refresh_token!(invoice.organization_id)

      assert_raise Cachex.Error, "unexpected transport failure", fn ->
        verify!(invoice, attempt: 3)
      end
    end)

    kept = SalesInvoice.by_id!(invoice.id, scope: scope_for(admin))
    assert kept.locked_at == invoice.locked_at
    assert kept.invoice_number == invoice.invoice_number
  end

  test "renews and caches a token while reconciling a successful submission" do
    admin = admin_fixture()
    invoice = submitted_invoice!(admin, %{ksef_invoice_kind: :vat})
    token = jwt(3600)

    Req.Test.stub(:ksef_api, fn conn ->
      case String.replace_prefix(conn.request_path, "/v2", "") do
        "/auth/token/refresh" ->
          Req.Test.json(conn, %{"accessToken" => %{"token" => token}})

        "/sessions/SESSION-REF/invoices/INVOICE-REF" ->
          Req.Test.json(conn, %{
            "status" => %{"code" => 200},
            "ksefNumber" => "KSEF-CONFIRMED",
            "invoiceHash" => "verified-hash"
          })
      end
    end)

    Oban.Testing.with_testing_mode(:manual, fn ->
      schedule_refresh_token!(invoice.organization_id)
      assert :ok = verify!(invoice)
    end)

    assert {:ok, ^token} = Cachex.get(:ksef, {:access_token, invoice.organization_id})
    Req.Test.stub(:ksef_api, fn _conn -> flunk("cached token triggered renewal") end)
    assert {:ok, ^token} = SessionWorker.get_access_token(invoice.organization_id)
    assert SessionWorker.get_access_token!(invoice.organization_id) == token

    assert SalesInvoice.by_id!(invoice.id, scope: scope_for(admin)).ksef_number ==
             "KSEF-CONFIRMED"
  end

  defp schedule_refresh_token!(organization_id) do
    refresh_token = 7200 |> jwt() |> Firmowid.Vault.encrypt!() |> Base.encode64()

    %{"organization_id" => organization_id, "refresh_token" => refresh_token}
    |> SessionWorker.new(schedule_in: 3600)
    |> Firmowid.Oban.insert!(skip_organization_id: true)
  end

  defp submitted_invoice!(admin, attrs) do
    %{
      invoice_number: "FV/#{System.unique_integer([:positive])}",
      issue_date: Date.utc_today(),
      sale_date: Date.utc_today(),
      due_date: Date.add(Date.utc_today(), 14),
      payment_method: :cash,
      currency: "PLN",
      seller_nip: "6161525811",
      seller_display_name: "Seller",
      seller_address: "Seller address",
      buyer_type: :company,
      buyer_id: "1111111111",
      buyer_full_name: "Buyer",
      buyer_address: "Buyer address",
      buyer_country: "PL",
      locked_at: DateTime.utc_now(:second),
      ksef_session_reference_number: "SESSION-REF",
      ksef_invoice_checksum: "pending_ref:INVOICE-REF",
      sales_invoice_items: [
        %{name: "Service", quantity: Decimal.new(1), unit: "szt", unit_price: Decimal.new(100)}
      ]
    }
    |> Map.merge(attrs)
    |> InvoicingFixtures.seed_sales_invoice!(scope: scope_for(admin))
  end

  defp reject_verification!(organization_id) do
    InvoicingFixtures.accept_ksef_submissions!(organization_id)

    Req.Test.stub(:ksef_api, fn conn ->
      Req.Test.json(conn, %{"status" => %{"code" => 450, "description" => "Invalid invoice"}})
    end)
  end

  defp verify!(invoice, opts \\ []) do
    perform_job(
      SubmissionWorker,
      %{
        "action" => "verify",
        "organization_id" => invoice.organization_id,
        "sales_invoice_id" => invoice.id,
        "session_reference" => "SESSION-REF",
        "invoice_reference" => "INVOICE-REF"
      },
      opts
    )
  end

  defp scope_for(user), do: %Scope{actor: user, tenant: user.member.organization_id}
end
