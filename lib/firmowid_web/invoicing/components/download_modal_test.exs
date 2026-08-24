defmodule FirmowidWeb.Invoicing.Components.DownloadModalTest do
  @moduledoc false
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Firmowid.Ash.Blobs.Blob
  alias Firmowid.Ash.Invoicing.CostInvoice

  test "download modal is rendered and builds month href with sales enabled by default", %{
    conn: conn
  } do
    admin = admin_fixture()
    current_month = Date.beginning_of_month(Date.utc_today())
    seed_cost_invoice!(admin.organization_id, current_month)

    {:ok, lv, html} = conn |> log_in_user(admin) |> live(~p"/fakturowanie")

    assert html =~ "Pobierz"

    rendered = render(lv)
    assert rendered =~ "Pobierz dokumenty"

    assert rendered =~ "/pobierz-miesiac?"
    assert rendered =~ "dolacz_sprzedazowe=tak"
  end

  defp seed_cost_invoice!(organization_id, issue_date) do
    blob =
      Ash.Seed.seed!(Blob, %{
        blob_path: "/test/path/modal-fixture.pdf",
        blob_checksum: "modal-fixture-checksum",
        original_filename: "modal-fixture.pdf",
        organization_id: organization_id
      })

    Ash.Seed.seed!(CostInvoice, %{
      seller: "Modal Seller",
      seller_display_name: "Modal Seller",
      invoice_identifier: "CI-MODAL-#{System.unique_integer([:positive])}",
      description: "Modal fixture",
      sale_date: issue_date,
      issue_date: issue_date,
      due_date: issue_date,
      amount: Money.new!("PLN", Decimal.new("-100.00")),
      organization_id: organization_id,
      blob_id: blob.id
    })
  end
end
