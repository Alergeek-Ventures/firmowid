defmodule Firmowid.Ksef.Workers.SubmissionWorkerTest do
  @moduledoc false
  use Firmowid.DataCase, async: false

  import Firmowid.AccountsFixtures
  import Firmowid.Ksef.KsefTestHelpers, only: [jwt: 1]

  alias Firmowid.Invoicing.SalesInvoice
  alias Firmowid.InvoicingFixtures
  alias Firmowid.Ksef.Credential
  alias Firmowid.Ksef.Services.InvoiceRenderer
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

  test "records the KSeF number of an invoice KSeF reports as a duplicate of itself" do
    admin = admin_fixture()
    invoice = submitted_invoice!(admin, %{ksef_invoice_kind: :vat})
    stored = invoice |> InvoiceRenderer.render_fa3() |> IO.iodata_to_binary()

    report_duplicate!(
      admin.member.organization_id,
      String.replace(
        stored,
        ~r/<DataWytworzeniaFa>[^<]*/,
        "<DataWytworzeniaFa>2026-01-01T00:00:00Z"
      )
    )

    assert :ok = verify!(invoice)

    confirmed = SalesInvoice.by_id!(invoice.id, scope: scope_for(admin))
    assert confirmed.ksef_number == "KSEF-FIRST-SENDING"
    assert confirmed.invoice_number == invoice.invoice_number
  end

  test "returns an invoice whose number another KSeF document has to a draft" do
    admin = admin_fixture()
    invoice = submitted_invoice!(admin, %{ksef_invoice_kind: :vat})
    stored = invoice |> InvoiceRenderer.render_fa3() |> IO.iodata_to_binary()

    report_duplicate!(
      admin.member.organization_id,
      String.replace(stored, "<P_7>Service</P_7>", "<P_7>Goods</P_7>")
    )

    assert {:cancel, {:invoice_duplicate, "KSEF-FIRST-SENDING", _session}} = verify!(invoice)

    withdrawn = SalesInvoice.by_id!(invoice.id, scope: scope_for(admin))
    assert is_nil(withdrawn.invoice_number)
    assert is_nil(withdrawn.ksef_number)
  end

  test "returns an invoice to a draft when KSeF does not give the document it duplicates" do
    admin = admin_fixture()
    invoice = submitted_invoice!(admin, %{ksef_invoice_kind: :vat})

    report_duplicate!(admin.member.organization_id, :not_found)

    assert {:error, {:unexpected_response, 404, _body}} = verify!(invoice)
    assert SalesInvoice.by_id!(invoice.id, scope: scope_for(admin)).invoice_number

    assert {:cancel, {:invoice_duplicate, "KSEF-FIRST-SENDING", _session}} =
             verify!(invoice, attempt: 3)

    assert is_nil(SalesInvoice.by_id!(invoice.id, scope: scope_for(admin)).invoice_number)
  end

  test "sends again an invoice KSeF cancelled on its side, up to a limit" do
    admin = admin_fixture()
    invoice = submitted_invoice!(admin, %{ksef_invoice_kind: :vat})
    InvoicingFixtures.accept_ksef_submissions!(invoice.organization_id)

    Req.Test.stub(:ksef_api, fn conn ->
      Req.Test.json(conn, %{"status" => %{"code" => 550, "description" => "Cancelled"}})
    end)

    Oban.Testing.with_testing_mode(:manual, fn ->
      assert :ok = verify!(invoice)

      assert_enqueued(
        worker: SubmissionWorker,
        args: %{"action" => "submit", "sales_invoice_id" => invoice.id, "resends" => 1},
        scheduled_at: {DateTime.shift(DateTime.utc_now(), minute: 1), delta: 5}
      )

      resent = SalesInvoice.by_id!(invoice.id, scope: scope_for(admin))
      assert resent.invoice_number == invoice.invoice_number
      assert is_nil(resent.locked_at)

      resent
      |> SalesInvoice.start_ksef_submission!(scope: ksef_scope(invoice.organization_id))
      |> SalesInvoice.record_ksef_submission!(
        %{
          ksef_session_reference_number: "SESSION-REF",
          ksef_invoice_checksum: "pending_ref:INVOICE-REF"
        },
        scope: ksef_scope(invoice.organization_id)
      )

      assert :ok = verify!(invoice, args: %{"resends" => 3})
      assert is_nil(SalesInvoice.by_id!(invoice.id, scope: scope_for(admin)).invoice_number)
    end)
  end

  test "a repeated verification leaves an invoice already sent again alone" do
    admin = admin_fixture()
    invoice = submitted_invoice!(admin, %{ksef_invoice_checksum: "pending_ref:RESENT-REF"})
    InvoicingFixtures.accept_ksef_submissions!(invoice.organization_id)

    Req.Test.stub(:ksef_api, fn conn ->
      Req.Test.json(conn, %{"status" => %{"code" => 550, "description" => "Cancelled"}})
    end)

    Oban.Testing.with_testing_mode(:manual, fn ->
      assert :ok = verify!(invoice, args: %{"resends" => 1})
      refute_enqueued(worker: SubmissionWorker)
    end)

    kept = SalesInvoice.by_id!(invoice.id, scope: scope_for(admin))
    assert kept.locked_at == invoice.locked_at
    assert kept.ksef_invoice_checksum == "pending_ref:RESENT-REF"
  end

  test "keeps checking an invoice of a disconnected organization without reauthenticating" do
    admin = admin_fixture()
    invoice = submitted_invoice!(admin, %{ksef_invoice_kind: :vat})
    scope = ksef_scope(invoice.organization_id)
    scope |> then(&Credential.get_internal!(scope: &1)) |> Credential.destroy!(scope: scope)

    Oban.Testing.with_testing_mode(:manual, fn ->
      assert {:snooze, 3600} = verify!(invoice)
      refute_enqueued(worker: SessionWorker)
    end)

    assert SalesInvoice.by_id!(invoice.id, scope: scope_for(admin)).locked_at == invoice.locked_at
  end

  test "keeps checking an invoice of an organization that is reconnecting without reauthenticating" do
    admin = admin_fixture()
    invoice = submitted_invoice!(admin, %{ksef_invoice_kind: :vat})

    Firmowid.Repo.query!(
      "UPDATE ksef_credentials SET status = 'wait_for_certificate' WHERE organization_id = $1",
      [
        Ecto.UUID.dump!(invoice.organization_id)
      ]
    )

    Oban.Testing.with_testing_mode(:manual, fn ->
      assert {:snooze, 3600} = verify!(invoice)
      refute_enqueued(worker: SessionWorker)
    end)

    assert SalesInvoice.by_id!(invoice.id, scope: scope_for(admin)).locked_at == invoice.locked_at
  end

  test "disconnecting from KSeF keeps the verification of an invoice KSeF is processing" do
    admin = admin_fixture()
    invoice = submitted_invoice!(admin, %{ksef_invoice_kind: :vat})
    InvoicingFixtures.accept_ksef_submissions!(invoice.organization_id)
    Req.Test.stub(:ksef_api, &Plug.Conn.send_resp(&1, 204, ""))

    Oban.Testing.with_testing_mode(:manual, fn ->
      verification =
        %{
          "action" => "verify",
          "organization_id" => invoice.organization_id,
          "sales_invoice_id" => invoice.id,
          "session_reference" => "SESSION-REF",
          "invoice_reference" => "INVOICE-REF"
        }
        |> SubmissionWorker.new()
        |> Firmowid.Oban.insert!(skip_organization_id: true)

      assert {:ok, :disconnected} = Firmowid.Ksef.unauthenticate(scope_for(admin))
      assert Firmowid.Repo.get!(Oban.Job, verification.id, oban_jobs: true).state == "available"
    end)
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

  test "sends again an invoice its interrupted earlier attempt left locked" do
    admin = admin_fixture()

    invoice =
      submitted_invoice!(admin, %{ksef_session_reference_number: nil, ksef_invoice_checksum: nil})

    InvoicingFixtures.accept_ksef_submissions!(invoice.organization_id)

    Oban.Testing.with_testing_mode(:manual, fn ->
      assert :ok =
               perform_job(
                 SubmissionWorker,
                 %{
                   "action" => "submit",
                   "organization_id" => invoice.organization_id,
                   "sales_invoice_id" => invoice.id
                 },
                 attempt: 2
               )
    end)

    assert SalesInvoice.by_id!(invoice.id, scope: scope_for(admin)).ksef_invoice_checksum ==
             "pending_ref:INVOICE-REF"
  end

  test "leaves a confirmed invoice alone when its submission is retried" do
    admin = admin_fixture()

    invoice =
      submitted_invoice!(admin, %{ksef_number: "KSEF-CONFIRMED", ksef_invoice_checksum: "hash"})

    assert {:cancel, :invoice_already_submitted} =
             perform_job(
               SubmissionWorker,
               %{
                 "action" => "submit",
                 "organization_id" => invoice.organization_id,
                 "sales_invoice_id" => invoice.id
               },
               attempt: 2
             )

    assert %{ksef_session_reference_number: "SESSION-REF", ksef_invoice_checksum: "hash"} =
             SalesInvoice.by_id!(invoice.id, scope: scope_for(admin))
  end

  test "retries a submission whose invoice cannot be read instead of cancelling it" do
    admin = admin_fixture()

    invoice =
      submitted_invoice!(admin, %{
        locked_at: nil,
        ksef_session_reference_number: nil,
        ksef_invoice_checksum: nil
      })

    # Hides the application tables from the rest of this test's sandbox transaction.
    Firmowid.Repo.query!("SET LOCAL search_path TO pg_catalog")

    assert {:error, %Ash.Error.Unknown{}} =
             perform_job(SubmissionWorker, %{
               "action" => "submit",
               "organization_id" => invoice.organization_id,
               "sales_invoice_id" => invoice.id
             })
  end

  defp schedule_refresh_token!(organization_id) do
    refresh_token = 7200 |> jwt() |> Firmowid.Vault.encrypt!() |> Base.encode64()

    %{"organization_id" => organization_id, "refresh_token" => refresh_token}
    |> SessionWorker.new(schedule_in: 3600)
    |> Firmowid.Oban.insert!(skip_organization_id: true)
  end

  defp submitted_invoice!(admin, attrs) do
    InvoicingFixtures.connect_ksef!(admin.member.organization_id)

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

  # KSeF rejects the sending as a duplicate of the document it stores under the given XML.
  defp report_duplicate!(organization_id, stored_xml) do
    InvoicingFixtures.accept_ksef_submissions!(organization_id)

    Req.Test.stub(:ksef_api, fn conn ->
      case String.replace_prefix(conn.request_path, "/v2", "") do
        "/sessions/SESSION-REF/invoices/INVOICE-REF" ->
          Req.Test.json(conn, %{
            "status" => %{
              "code" => 440,
              "extensions" => %{
                "originalKsefNumber" => "KSEF-FIRST-SENDING",
                "originalSessionReferenceNumber" => "FIRST-SESSION"
              }
            }
          })

        "/invoices/ksef/KSEF-FIRST-SENDING" when stored_xml == :not_found ->
          Plug.Conn.send_resp(conn, 404, "")

        "/invoices/ksef/KSEF-FIRST-SENDING" ->
          Plug.Conn.send_resp(conn, 200, stored_xml)
      end
    end)
  end

  defp verify!(invoice, opts \\ []) do
    {args, opts} = Keyword.pop(opts, :args, %{})

    perform_job(
      SubmissionWorker,
      Map.merge(
        %{
          "action" => "verify",
          "organization_id" => invoice.organization_id,
          "sales_invoice_id" => invoice.id,
          "session_reference" => "SESSION-REF",
          "invoice_reference" => "INVOICE-REF"
        },
        args
      ),
      opts
    )
  end

  defp ksef_scope(organization_id) do
    %Scope{
      actor: %Firmowid.SystemActor{org_id: organization_id, role: :ksef_session},
      tenant: organization_id
    }
  end

  defp scope_for(user), do: %Scope{actor: user, tenant: user.member.organization_id}
end
