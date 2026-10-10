defmodule FirmowidWeb.Invoicing.SalesInvoices.Views.EditTest do
  @moduledoc false
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Firmowid.Ash.Finances
  alias Firmowid.Ash.Invoicing.SalesInvoice

  test "draft review preserves edits and confirms the selected custom number", %{conn: conn} do
    admin = admin_fixture()
    scope = %{tenant: admin.organization_id, actor: admin}
    invoice = draft_fixture!(admin)

    conn = log_in_user(conn, admin)
    {:ok, view, _html} = live(conn, ~p"/sprzedazowe/#{invoice.id}/edytuj")

    view
    |> form("#invoice-form", form: %{internal_note: "Changed before review"})
    |> render_submit()

    assert has_element?(view, "#invoice-review")
    assert has_element?(view, "#back-to-edit", "Wróć")
    assert has_element?(view, "#internal-note", "Changed before review")
    assert is_nil(SalesInvoice.get!(invoice.id, scope: scope).invoice_number)

    view
    |> form("#invoice-number-form", invoice_number: "CUSTOM/2026/42")
    |> render_change()

    view
    |> form("#invoice-notes-form", invoice_note: "Visible note", internal_note: "Private comment")
    |> render_change()

    view |> element("#back-to-edit") |> render_click()

    assert has_element?(
             view,
             "#invoice-form textarea[name='form[internal_note]']",
             "Private comment"
           )

    view |> form("#invoice-form") |> render_submit()
    assert has_element?(view, "#invoice-number[value='CUSTOM/2026/42']")

    view |> element("#confirm-invoice-button") |> render_click()
    assert_redirect(view, ~p"/sprzedazowe/#{invoice.id}/podsumowanie")

    confirmed = SalesInvoice.get!(invoice.id, scope: scope)
    assert confirmed.invoice_number == "CUSTOM/2026/42"
    assert confirmed.invoice_note == "Visible note"
    assert confirmed.internal_note == "Private comment"
  end

  test "saving from draft review keeps the invoice unnumbered", %{conn: conn} do
    admin = admin_fixture()
    scope = %{tenant: admin.organization_id, actor: admin}
    invoice = draft_fixture!(admin)
    conn = log_in_user(conn, admin)
    {:ok, view, _html} = live(conn, ~p"/sprzedazowe/#{invoice.id}/edytuj")

    view |> form("#invoice-form") |> render_submit()
    view |> form("#invoice-number-form", invoice_number: "") |> render_change()
    assert has_element?(view, "#confirm-invoice-button[disabled]")
    view |> form("#invoice-number-form", invoice_number: "") |> render_submit()
    assert has_element?(view, "#invoice-review")
    assert is_nil(SalesInvoice.get!(invoice.id, scope: scope).invoice_number)
    view |> form("#invoice-number-form", invoice_number: "NOT-YET-ISSUED") |> render_change()
    view |> element("#invoice-review button[phx-click='save_as_draft']") |> render_click()
    assert_redirect(view, ~p"/sprzedazowe/#{invoice.id}")
    assert is_nil(SalesInvoice.get!(invoice.id, scope: scope).invoice_number)
  end

  defp draft_fixture!(admin) do
    admin.organization_id
    |> Firmowid.Ash.Core.get_organization!(actor: admin, tenant: admin.organization_id)
    |> Ash.Seed.update!(%{address: "Seller address"})

    Ash.Seed.seed!(SalesInvoice, %{
      organization_id: admin.organization_id,
      issue_date: Date.utc_today(),
      sale_date: Date.utc_today(),
      due_date: Date.add(Date.utc_today(), 7),
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

  test "payment step selects the invoice-currency account for a formatted legacy IBAN", %{
    conn: conn
  } do
    admin = admin_fixture()
    scope = %{tenant: admin.organization_id, actor: admin}
    iban = "DE02120300000000202020202020"

    {:ok, pln_account} =
      Finances.create_manual_bank_account(
        %{iban: iban, name: "Rachunek PLN", currency: "PLN", is_default: false},
        scope: scope
      )

    {:ok, eur_account} =
      Finances.create_manual_bank_account(
        %{iban: iban, name: "Rachunek EUR", currency: "EUR", is_default: false},
        scope: scope
      )

    {:ok, invoice} =
      SalesInvoice.create(
        %{
          invoice_number: "FV/TEST/ACCOUNT",
          issue_date: Date.utc_today(),
          sale_date: Date.utc_today(),
          due_date: Date.add(Date.utc_today(), 14),
          payment_method: :transfer,
          invoice_type: :foreign,
          currency: "EUR",
          seller_account_number: "de02 1203 0000 0000 2020 2020 2020",
          seller_nip: "6161525811",
          seller_display_name: "Bytecraft",
          seller_address: "Address",
          buyer_type: :company,
          buyer_id: "1111111111",
          buyer_full_name: "Buyer Company",
          buyer_display_name: "Buyer",
          buyer_address: "Buyer address",
          buyer_country: "PL",
          sales_invoice_items: [
            %{
              index: 0,
              name: "Line",
              quantity: Decimal.new("2"),
              unit: "szt",
              unit_price: Decimal.new("10"),
              vat_rate: "np I"
            }
          ]
        },
        tenant: admin.organization_id,
        actor: admin
      )

    conn = log_in_user(conn, admin)
    {:ok, view, _html} = live(conn, ~p"/sprzedazowe/#{invoice.id}/edytuj")
    assert has_element?(view, "#bank-account-option-#{pln_account.id}", "PLN")
    assert has_element?(view, "#bank-account-option-#{eur_account.id}", "EUR")
    assert has_element?(view, "#bank-account-option-#{pln_account.id} button", "Wybierz")
    assert has_element?(view, "#bank-account-option-#{eur_account.id} button", "Odznacz")
  end

  test "editing foreign invoice does not crash preview money rendering", %{conn: conn} do
    admin = admin_fixture()

    {:ok, invoice} =
      SalesInvoice.create(
        %{
          invoice_number: "FV/TEST/1",
          issue_date: Date.utc_today(),
          sale_date: Date.utc_today(),
          due_date: Date.add(Date.utc_today(), 14),
          payment_method: :transfer,
          invoice_type: :foreign,
          currency: "EUR",
          seller_nip: "6161525811",
          seller_display_name: "Bytecraft",
          seller_address: "Address",
          buyer_type: :company,
          buyer_id: "1111111111",
          buyer_full_name: "Buyer Company",
          buyer_display_name: "Buyer",
          buyer_address: "Buyer address",
          buyer_country: "PL",
          sales_invoice_items: [
            %{
              index: 0,
              name: "Line",
              quantity: Decimal.new("2"),
              unit: "szt",
              unit_price: Decimal.new("10"),
              vat_rate: "np I"
            }
          ]
        },
        tenant: admin.organization_id,
        actor: admin
      )

    conn = log_in_user(conn, admin)

    assert {:ok, _view, html} = live(conn, ~p"/sprzedazowe/#{invoice.id}/edytuj")
    assert html =~ "Fakturowanie"
  end

  test "editing a KSeF invoice renders the correction preview amount", %{conn: conn} do
    admin = admin_fixture()

    {:ok, invoice} =
      SalesInvoice.create(
        %{
          invoice_number: "FV/TEST/KSEF",
          issue_date: Date.utc_today(),
          sale_date: Date.utc_today(),
          due_date: Date.add(Date.utc_today(), 14),
          payment_method: :transfer,
          invoice_type: :foreign,
          currency: "EUR",
          seller_nip: "6161525811",
          seller_display_name: "Bytecraft",
          seller_address: "Address",
          buyer_type: :company,
          buyer_id: "1111111111",
          buyer_full_name: "Buyer Company",
          buyer_display_name: "Buyer",
          buyer_address: "Buyer address",
          buyer_country: "PL",
          sales_invoice_items: [
            %{
              index: 0,
              name: "Line",
              quantity: Decimal.new("2"),
              unit: "szt",
              unit_price: Decimal.new("10"),
              vat_rate: "np I"
            }
          ]
        },
        tenant: admin.organization_id,
        actor: admin
      )

    Ash.Seed.update!(invoice, %{
      ksef_number: "KSEF-TEST",
      ksef_invoice_checksum: "test-checksum"
    })

    conn = log_in_user(conn, admin)

    assert {:ok, _view, html} = live(conn, ~p"/sprzedazowe/#{invoice.id}/edytuj")
    assert html =~ "Faktura korygująca"
  end

  test "payment suggestions set due date from invoice issue date in edit", %{conn: conn} do
    admin = admin_fixture()

    {:ok, invoice} =
      SalesInvoice.create(
        %{
          invoice_number: "FV/TEST/2",
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
          buyer_display_name: "Buyer",
          buyer_address: "Buyer address",
          buyer_country: "PL",
          sales_invoice_items: [
            %{
              index: 0,
              name: "Line",
              quantity: Decimal.new("2"),
              unit: "szt",
              unit_price: Decimal.new("10"),
              vat_rate: "np I"
            }
          ]
        },
        tenant: admin.organization_id,
        actor: admin
      )

    conn = log_in_user(conn, admin)

    {:ok, view, _html} = live(conn, ~p"/sprzedazowe/#{invoice.id}/edytuj")

    view
    |> element("button[phx-click='suggest_payment_date'][phx-value-field='due_date'][phx-value-suggestion='days_7']")
    |> render_click()

    assert render(view) =~ ~s(value="2026-01-17")
  end

  test "confirmed invoice opens the edit form unless it is locked", %{conn: conn} do
    admin = admin_fixture()

    {:ok, invoice} =
      SalesInvoice.create(
        %{
          invoice_number: "FV/TEST/3",
          issue_date: Date.utc_today(),
          sale_date: Date.utc_today(),
          due_date: Date.add(Date.utc_today(), 14),
          payment_method: :transfer,
          invoice_type: :foreign,
          currency: "EUR",
          seller_nip: "6161525811",
          seller_display_name: "Bytecraft",
          seller_address: "Address",
          buyer_type: :company,
          buyer_id: "1111111111",
          buyer_full_name: "Buyer Company",
          buyer_display_name: "Buyer",
          buyer_address: "Buyer address",
          buyer_country: "PL",
          sales_invoice_items: [
            %{
              index: 0,
              name: "Line",
              quantity: Decimal.new("2"),
              unit: "szt",
              unit_price: Decimal.new("10"),
              vat_rate: "np I"
            }
          ]
        },
        tenant: admin.organization_id,
        actor: admin
      )

    conn = log_in_user(conn, admin)

    assert {:ok, _view, html} = live(conn, ~p"/sprzedazowe/#{invoice.id}/edytuj")
    assert html =~ "Edycja faktury"

    Ash.Seed.update!(invoice, %{locked_at: DateTime.utc_now()})
    show_path = "/sprzedazowe/#{invoice.id}"

    assert {:error,
            {:live_redirect,
             %{
               to: ^show_path,
               flash: %{
                 "error" => "Nie można edytować tej faktury — jest zablokowana podczas wysyłki do KSeF."
               }
             }}} = live(conn, ~p"/sprzedazowe/#{invoice.id}/edytuj")
  end
end
