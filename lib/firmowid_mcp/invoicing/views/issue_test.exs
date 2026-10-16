defmodule FirmowidMcp.Invoicing.Views.IssueTest do
  @moduledoc false
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias FirmowidMcp.Invoicing.IssueInvoice
  alias FirmowidMcp.Invoicing.Views.Issue

  test "issues a resumed draft today with the chosen number and notes", %{conn: conn} do
    admin = admin_fixture()
    saved_on = Date.add(Date.utc_today(), -40)
    draft = draft_fixture!(admin, saved_on)
    Firmowid.InvoicingFixtures.accept_ksef_submissions!(admin.organization_id)

    conn =
      conn
      |> Plug.Conn.assign(:oauth_claims, %{"exp" => System.system_time(:second) + 600})
      |> Ash.PlugHelpers.set_actor(admin)
      |> Ash.PlugHelpers.set_tenant(admin.organization_id)

    arguments = %{"input" => %{"input" => %{}, "invoice_id" => draft.id}}
    token = FirmowidMcp.Session.issue(conn, IssueInvoice.resource_uri(), arguments)

    {:ok, view, html} =
      live_isolated(conn, Issue, session: %{"mcp_session" => token, "mcp_resource" => IssueInvoice.resource_uri()})

    assert html =~ Calendar.strftime(Date.utc_today(), "%d.%m.%Y")
    refute html =~ Calendar.strftime(saved_on, "%d.%m.%Y")

    assert view
           |> form("#invoice-number-form", invoice_number: "not a number")
           |> render_change() =~ "Format numeru może być nieprawidłowy."

    view |> form("#invoice-number-form", invoice_number: "FV/NOTES/1") |> render_change()

    view
    |> form("#invoice-notes-form", invoice_note: "Visible note", internal_note: "Private comment")
    |> render_change()

    view |> element("#confirm-invoice-issuance") |> render_click()

    issued = SalesInvoice.get!(draft.id, scope: %{tenant: admin.organization_id, actor: admin})

    assert {issued.invoice_number, issued.invoice_note, issued.internal_note} ==
             {"FV/NOTES/1", "Visible note", "Private comment"}
  end

  defp draft_fixture!(admin, saved_on) do
    admin.organization_id
    |> Firmowid.Ash.Core.get_organization!(actor: admin, tenant: admin.organization_id)
    |> Ash.Seed.update!(%{address: "Seller address"})

    Ash.Seed.seed!(SalesInvoice, %{
      organization_id: admin.organization_id,
      issue_date: saved_on,
      sale_date: Date.utc_today(),
      due_date: Date.add(Date.utc_today(), 7),
      payment_method: :cash,
      currency: "PLN",
      buyer_type: :company,
      buyer_country: "PL",
      buyer_id: "1111111111",
      buyer_full_name: "Buyer Company",
      buyer_address: "Buyer address",
      sales_invoice_items: [
        %{
          organization_id: admin.organization_id,
          index: 0,
          name: "Consulting",
          quantity: Decimal.new(1),
          unit: "szt",
          unit_price: Decimal.new(100),
          vat_rate: "23"
        }
      ]
    })
  end
end
