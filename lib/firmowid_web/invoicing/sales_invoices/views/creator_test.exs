defmodule FirmowidWeb.Invoicing.SalesInvoices.Views.CreatorTest do
  @moduledoc false
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Firmowid.Ash.Invoicing.WizardDraft

  test "payment suggestions set due date from issue date in creator", %{conn: conn} do
    admin = admin_fixture()
    draft = payment_step_draft!(admin)
    conn = log_in_user(conn, admin)

    {:ok, view, _html} = live(conn, ~p"/sprzedazowe?szkic_kreatora=#{draft.id}&krok=3")

    view
    |> element("button[phx-click='suggest_payment_date'][phx-value-field='due_date'][phx-value-suggestion='days_7']")
    |> render_click()

    assert render(view) =~ ~s(value="#{Date.to_iso8601(Date.add(Date.utc_today(), 7))}")
  end

  test "items step shows one empty row by default", %{conn: conn} do
    admin = admin_fixture()
    draft = items_step_draft!(admin)
    conn = log_in_user(conn, admin)

    {:ok, _view, html} = live(conn, ~p"/sprzedazowe?szkic_kreatora=#{draft.id}&krok=2")

    assert html =~ "Wprowadź nazwę"
  end

  test "counterparty step derives invoice defaults in wizard action", %{conn: conn} do
    admin = admin_fixture()
    conn = log_in_user(conn, admin)
    scope = [tenant: admin.organization_id, actor: admin, authorize?: false]

    {:ok, draft} = WizardDraft.create(%{organization_id: admin.organization_id}, scope)

    {:ok, updated_draft} =
      WizardDraft.update_counterparty(
        draft,
        %{
          buyer_type: :company,
          buyer_id: "DE123456789",
          buyer_full_name: "Buyer GmbH",
          buyer_address: "Teststrasse 1",
          buyer_country: "DE"
        },
        scope
      )

    assert updated_draft.invoice_type == :foreign
    assert updated_draft.currency == "EUR"
    assert updated_draft.is_reverse_charge == true

    {:ok, _view, _html} = live(conn, ~p"/sprzedazowe?szkic_kreatora=#{updated_draft.id}&krok=2")
  end

  defp payment_step_draft!(admin) do
    scope = [tenant: admin.organization_id, actor: admin]

    {:ok, draft} = WizardDraft.create(%{organization_id: admin.organization_id}, scope)

    {:ok, draft} =
      WizardDraft.update_items(
        draft,
        %{
          currency: "PLN",
          items: [
            %{
              index: 0,
              name: "Usługa",
              quantity: Decimal.new("1"),
              unit: "szt.",
              unit_price: Decimal.new("100.00"),
              vat_rate: "23"
            }
          ]
        },
        scope
      )

    draft
  end

  defp items_step_draft!(admin) do
    scope = [tenant: admin.organization_id, actor: admin]

    {:ok, draft} = WizardDraft.create(%{organization_id: admin.organization_id}, scope)

    {:ok, draft} =
      WizardDraft.update_counterparty(
        draft,
        %{
          buyer_type: :individual,
          buyer_given_name: "Jan",
          buyer_surname: "Kowalski",
          buyer_pesel: "44051401359",
          buyer_address: "ul. Testowa 1",
          buyer_country: "PL"
        },
        scope
      )

    draft
  end
end
