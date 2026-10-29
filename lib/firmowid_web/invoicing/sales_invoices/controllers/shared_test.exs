defmodule FirmowidWeb.Invoicing.SalesInvoices.Controllers.SharedTest do
  @moduledoc false
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures

  alias Firmowid.Blobs.Blob
  alias Firmowid.Core
  alias Firmowid.Invoicing.SalesInvoice
  alias Firmowid.Scope
  alias Firmowid.SystemActor

  setup do
    user = admin_fixture()
    token = "shared-#{System.unique_integer([:positive])}"
    invoice = invoice_fixture(user.member.organization_id, token)
    %{user: user, token: token, invoice: invoice}
  end

  test "renders a token-authorized public preview without a logo", %{conn: conn, token: token} do
    assert conn |> get(~p"/faktura/#{token}") |> html_response(200) =~ "Synthetic Seller"
  end

  test "renders only the shared organization's logo", %{conn: conn, user: user, token: token} do
    logo = logo_fixture(user.member.organization_id)
    organization = Core.get_organization!(user.member.organization_id, scope: scope_for(user))
    Ash.Seed.update!(organization, %{avatar_blob_id: logo.id})

    html = conn |> get(~p"/faktura/#{token}") |> html_response(200)
    assert html =~ logo.blob_path
  end

  test "does not expose a logo belonging to another tenant", %{
    conn: conn,
    user: user,
    token: token
  } do
    other_user = admin_fixture()
    logo = logo_fixture(other_user.member.organization_id)
    organization = Core.get_organization!(user.member.organization_id, scope: scope_for(user))
    Ash.Seed.update!(organization, %{avatar_blob_id: logo.id})

    html = conn |> get(~p"/faktura/#{token}") |> html_response(200)
    refute html =~ logo.blob_path
  end

  test "rejects invalid tokens for preview and PDF", %{conn: conn} do
    assert conn |> get(~p"/faktura/invalid-token") |> html_response(404)
    assert build_conn() |> get(~p"/faktura/invalid-token/pdf") |> html_response(404)
  end

  test "a root token cannot select another tenant's invoice as a correction", %{
    conn: conn,
    token: token
  } do
    other_user = admin_fixture()
    other_invoice = invoice_fixture(other_user.member.organization_id, "other-token")
    pdf_token = "#{token}.#{other_invoice.id}"

    assert conn |> get(~p"/faktura/#{pdf_token}/pdf") |> html_response(404)
  end

  test "public access does not grant a general organization read", %{user: user} do
    anonymous_scope = %Scope{
      actor: %SystemActor{org_id: user.member.organization_id, role: :anonymous},
      tenant: user.member.organization_id
    }

    assert {:error, _} =
             Core.get_organization(user.member.organization_id, scope: anonymous_scope)
  end

  test "a shared chain remains bound to its token and tenant", %{
    user: user,
    invoice: invoice,
    token: token
  } do
    other_user = admin_fixture()
    other_invoice = invoice_fixture(other_user.member.organization_id, "foreign-token")

    scope = %Scope{
      actor: %SystemActor{org_id: user.member.organization_id, role: :anonymous},
      tenant: user.member.organization_id
    }

    assert SalesInvoice.public_shared_chain!(invoice.id, "invalid-token", scope: scope) == []

    assert SalesInvoice.public_shared_chain!(other_invoice.id, "foreign-token", scope: scope) ==
             []

    assert SalesInvoice.public_shared_chain!(other_invoice.id, token, scope: scope) == []
  end

  defp invoice_fixture(organization_id, token) do
    Ash.Seed.seed!(SalesInvoice, %{
      invoice_number: "FV/SYNTHETIC/1",
      sale_date: ~D[2026-01-01],
      issue_date: ~D[2026-01-01],
      due_date: ~D[2026-01-15],
      payment_method: :transfer,
      currency: "PLN",
      buyer_type: :company,
      buyer_id: "1234567890",
      buyer_full_name: "Synthetic Buyer",
      buyer_address: "Testowa 1",
      buyer_country: "PL",
      seller_display_name: "Synthetic Seller",
      seller_nip: "1234567890",
      seller_address: "Testowa 2",
      organization_id: organization_id,
      locked_at: DateTime.utc_now(:second),
      share_token: token,
      sales_invoice_items: [
        %{
          organization_id: organization_id,
          index: 0,
          name: "Synthetic service",
          quantity: Decimal.new(1),
          unit: "szt.",
          unit_price: Decimal.new(100),
          vat_rate: "23"
        }
      ]
    })
  end

  defp logo_fixture(organization_id) do
    Ash.Seed.seed!(Blob, %{
      organization_id: organization_id,
      blob_path: "synthetic-logo-#{System.unique_integer([:positive])}.png",
      blob_checksum: "synthetic-checksum",
      original_filename: "logo.png"
    })
  end

  defp scope_for(user), do: %Scope{actor: user, tenant: user.member.organization_id}
end
