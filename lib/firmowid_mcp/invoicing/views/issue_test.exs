defmodule FirmowidMcp.Invoicing.Views.IssueTest do
  @moduledoc false
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Firmowid.Invoicing
  alias Firmowid.Invoicing.SalesInvoice
  alias Firmowid.Invoicing.SalesInvoice.Preview
  alias FirmowidMcp.Invoicing.IssueInvoice
  alias FirmowidMcp.Invoicing.Views.Issue

  test "issues a resumed draft today with the chosen number and notes", %{conn: conn} do
    admin = admin_fixture()
    saved_on = Date.add(Date.utc_today(), -40)
    draft = draft_fixture!(admin, saved_on)
    Firmowid.InvoicingFixtures.accept_ksef_submissions!(admin.member.organization_id)

    conn =
      conn
      |> Plug.Conn.assign(:oauth_claims, registered_claims(admin))
      |> Ash.PlugHelpers.set_actor(admin)
      |> Ash.PlugHelpers.set_tenant(admin.member.organization_id)

    arguments = %{"input" => %{"invoice" => %{}, "invoice_id" => draft.id}}
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

    issued =
      SalesInvoice.get!(draft.id, scope: %{tenant: admin.member.organization_id, actor: admin})

    assert {issued.invoice_number, issued.invoice_note, issued.internal_note} ==
             {"FV/NOTES/1", "Visible note", "Private comment"}
  end

  for changed_field <- [:should_send_emails, :gtu] do
    @changed_field changed_field
    test "requires another review after a saved draft changes #{@changed_field}", %{conn: conn} do
      admin = admin_fixture()
      editor = user_in_org_fixture(admin.member.organization_id, %{role: :accountant})
      scope = %{tenant: admin.member.organization_id, actor: admin}
      draft = draft_fixture!(admin, Date.utc_today())
      Firmowid.InvoicingFixtures.accept_ksef_submissions!(admin.member.organization_id)

      conn =
        conn
        |> Plug.Conn.assign(:oauth_claims, registered_claims(admin))
        |> Ash.PlugHelpers.set_actor(admin)
        |> Ash.PlugHelpers.set_tenant(admin.member.organization_id)

      arguments = %{"input" => %{"invoice" => %{}, "invoice_id" => draft.id}}
      token = FirmowidMcp.Session.issue(conn, IssueInvoice.resource_uri(), arguments)

      {:ok, view, _html} =
        live_isolated(conn, Issue, session: %{"mcp_session" => token, "mcp_resource" => IssueInvoice.resource_uri()})

      reviewed =
        Invoicing.preview_sales_invoice!(%{invoice_id: draft.id, invoice: %{}}, scope: scope)

      expected_review = Preview.review_snapshot(%{reviewed | invoice_number: "FV/ATOMIC/1"})

      input =
        case @changed_field do
          :should_send_emails ->
            %{should_send_emails: true}

          :gtu ->
            items = Ash.load!(draft, :sales_invoice_items, scope: scope).sales_invoice_items

            %{
              sales_invoice_items:
                Enum.map(items, fn item ->
                  item
                  |> Map.take([:id, :index, :name, :quantity, :unit, :unit_price, :vat_rate])
                  |> Map.put(:gtu, "GTU_02")
                end)
            }
        end

      Invoicing.revise_sales_invoice_draft!(draft, %{input: input},
        scope: %{tenant: admin.member.organization_id, actor: editor}
      )

      assert {:error, error} =
               Invoicing.finalize_sales_invoice_draft(
                 draft,
                 %{
                   input: %{
                     invoice_number: "FV/ATOMIC/1",
                     issue_date: Date.utc_today(),
                     invoice_note: reviewed.invoice_note,
                     internal_note: reviewed.internal_note
                   }
                 },
                 scope: scope,
                 private_arguments: %{expected_review: expected_review}
               )

      assert Exception.message(error) =~
               "The invoice data changed. Review the updated preview and confirm again."

      view |> element("#confirm-invoice-issuance") |> render_click()

      assert is_nil(SalesInvoice.get!(draft.id, scope: scope).invoice_number)
      assert has_element?(view, "[role=alert]")

      view |> element("#confirm-invoice-issuance") |> render_click()
      issued = SalesInvoice.get!(draft.id, scope: scope, load: [:sales_invoice_items])
      assert issued.invoice_number

      case @changed_field do
        :should_send_emails -> assert issued.should_send_emails
        :gtu -> assert Enum.map(issued.sales_invoice_items, & &1.gtu) == ["GTU_02"]
      end
    end
  end

  defp registered_claims(user) do
    {:ok, token, claims} =
      AshAuthentication.Oauth2Server.Jwt.mint(Firmowid.Oauth2Server,
        sub: user.id,
        client_id: Ash.UUIDv7.generate(),
        scope: "mcp",
        ttl: 600
      )

    FirmowidMcp.Utilities.AccessToken.store!(token, user)
    claims
  end

  defp draft_fixture!(admin, saved_on) do
    admin.member.organization_id
    |> Firmowid.Core.get_organization!(actor: admin, tenant: admin.member.organization_id)
    |> Ash.Seed.update!(%{address: "Seller address"})

    Ash.Seed.seed!(SalesInvoice, %{
      organization_id: admin.member.organization_id,
      issue_date: saved_on,
      sale_date: Date.utc_today(),
      due_date: Date.add(Date.utc_today(), 7),
      payment_method: :cash,
      currency: "PLN",
      should_send_emails: false,
      buyer_type: :company,
      buyer_country: "PL",
      buyer_id: "1111111111",
      buyer_full_name: "Buyer Company",
      buyer_address: "Buyer address",
      sales_invoice_items: [
        %{
          organization_id: admin.member.organization_id,
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
