defmodule Firmowid.KsefTest do
  @moduledoc false
  use Firmowid.DataCase, async: false

  import Firmowid.AccountsFixtures

  alias Firmowid.Invoicing.SalesInvoice
  alias Firmowid.InvoicingFixtures
  alias Firmowid.Ksef
  alias Firmowid.Scope

  setup do
    on_exit(fn -> Cachex.clear(:ksef) end)
  end

  test "invoice_url! stores the checksum of an accepted sales invoice that has none" do
    admin = admin_fixture()
    scope = %Scope{actor: admin, tenant: admin.member.organization_id}
    xml = "<Faktura>accepted</Faktura>"

    invoice =
      InvoicingFixtures.seed_sales_invoice!(
        %{
          invoice_number: "FV/1",
          issue_date: ~D[2026-01-15],
          sale_date: ~D[2026-01-15],
          due_date: ~D[2026-01-29],
          payment_method: :cash,
          currency: "PLN",
          seller_nip: "6161525811",
          seller_display_name: "Acme Sp. z o.o.",
          seller_address: "ul. Przykładowa 1, 00-001 Warszawa",
          buyer_type: :company,
          buyer_id: "1111111111",
          buyer_full_name: "Buyer",
          buyer_address: "Buyer address",
          buyer_country: "PL",
          locked_at: DateTime.utc_now(:second),
          ksef_number: "6161525811-20260115-ABCDEF-ABCDEF-AB",
          ksef_invoice_checksum: nil,
          sales_invoice_items: [
            %{
              name: "Service",
              quantity: Decimal.new(1),
              unit: "szt",
              unit_price: Decimal.new(100)
            }
          ]
        },
        scope: scope
      )

    InvoicingFixtures.accept_ksef_submissions!(scope.tenant)
    Req.Test.stub(:ksef_api, fn conn -> Plug.Conn.send_resp(conn, 200, xml) end)

    checksum = Ksef.compute_fa3_checksum(xml)

    assert Ksef.invoice_url!(invoice) =~ "/6161525811/15-01-2026/#{checksum}"
    assert SalesInvoice.by_id!(invoice.id, scope: scope).ksef_invoice_checksum == checksum
  end
end
