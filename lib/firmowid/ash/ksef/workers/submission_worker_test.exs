defmodule Firmowid.Ash.Ksef.Workers.SubmissionWorkerTest do
  @moduledoc false
  use Firmowid.DataCase, async: false

  import Firmowid.AccountsFixtures

  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Ksef.Workers.SubmissionWorker
  alias Firmowid.Ash.Scope
  alias Firmowid.InvoicingFixtures

  setup do
    on_exit(fn -> Cachex.clear(:ksef) end)
  end

  test "returns a VAT invoice KSeF rejected to an unnumbered draft" do
    admin = admin_fixture()
    invoice = submitted_invoice!(admin, %{ksef_invoice_kind: :vat})

    reject_verification!(admin.organization_id)
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

    reject_verification!(admin.organization_id)
    verify!(correction)

    assert {:ok, nil} =
             SalesInvoice.by_id(correction.id, scope: scope_for(admin), not_found_error?: false)
  end

  test "keeps an invoice KSeF is still processing after the polling limit and checks it hourly" do
    admin = admin_fixture()
    invoice = submitted_invoice!(admin, %{ksef_invoice_kind: :vat})

    InvoicingFixtures.accept_ksef_submissions!(admin.organization_id)

    Req.Test.stub(:ksef_api, fn conn ->
      Req.Test.json(conn, %{"status" => %{"code" => 150, "description" => "Processing"}})
    end)

    assert {:snooze, 3600} = verify!(invoice, meta: %{"snoozed" => 360})

    kept = SalesInvoice.by_id!(invoice.id, scope: scope_for(admin))
    assert kept.invoice_number == invoice.invoice_number
    assert kept.locked_at
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

  defp scope_for(user), do: %Scope{actor: user, tenant: user.organization_id}
end
