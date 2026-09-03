defmodule FirmowidWeb.Invoicing.SalesInvoices.Views.CreatorTest do
  @moduledoc false
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Firmowid.Ash.Finances
  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Invoicing.WizardDraft
  alias Firmowid.Ash.Scope
  alias Firmowid.Test.Support.InvoicingCopyAssertions

  test "payment step restores the bank account matching the draft currency", %{conn: conn} do
    admin = admin_fixture()
    scope = scope_for(admin)
    iban = "DE02120300000000202020202020"

    {:ok, pln_account} =
      Finances.create_manual_bank_account(
        %{iban: iban, name: "Rachunek PLN", currency: "PLN", is_default: false},
        scope: scope
      )

    {:ok, eur_account} =
      Finances.create_manual_bank_account(
        %{iban: iban, name: "Rachunek EUR", currency: "EUR", is_default: true},
        scope: scope
      )

    draft = payment_step_draft!(admin)

    formatted_iban = "de02 1203 0000 0000 2020 2020 2020"

    {:ok, draft} =
      WizardDraft.update_payment(
        draft,
        %{
          seller_account_number: formatted_iban,
          sale_date: Date.utc_today(),
          due_date: Date.add(Date.utc_today(), 14),
          payment_method: :transfer
        },
        scope: scope
      )

    conn = log_in_user(conn, admin)
    {:ok, view, _html} = live(conn, ~p"/sprzedazowe?szkic_kreatora=#{draft.id}&krok=3")

    assert has_element?(view, "#bank-account-option-#{pln_account.id}", "PLN")
    assert has_element?(view, "#bank-account-option-#{eur_account.id}", "EUR")
    assert has_element?(view, "#bank-account-option-#{pln_account.id} button", "Odznacz")
    assert has_element?(view, "#bank-account-option-#{eur_account.id} button", "Wybierz")
  end

  test "payment step does not replace an unmatched IBAN with the currency default", %{
    conn: conn
  } do
    admin = admin_fixture()
    scope = scope_for(admin)

    {:ok, default_account} =
      Finances.create_manual_bank_account(
        %{
          iban: "PL61109010140000071219812874",
          name: "Rachunek PLN",
          currency: "PLN",
          is_default: true
        },
        scope: scope
      )

    draft = payment_step_draft!(admin)

    {:ok, draft} =
      WizardDraft.update_payment(
        draft,
        %{
          seller_account_number: "PL16109010140000071219812875",
          sale_date: Date.utc_today(),
          due_date: Date.add(Date.utc_today(), 14),
          payment_method: :transfer
        },
        scope: scope
      )

    conn = log_in_user(conn, admin)
    {:ok, view, _html} = live(conn, ~p"/sprzedazowe?szkic_kreatora=#{draft.id}&krok=3")

    assert has_element?(view, "#bank-account-option-#{default_account.id} button", "Wybierz")
  end

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

  test "items step gross price display uses unit price in net mode", %{conn: conn} do
    admin = admin_fixture()
    draft = items_step_draft!(admin)
    scope = [tenant: admin.organization_id, actor: admin]

    {:ok, draft} =
      WizardDraft.update_items(
        draft,
        %{
          currency: "PLN",
          items: [
            %{
              index: 0,
              name: "Usługa brutto",
              quantity: Decimal.new("2"),
              unit: "szt.",
              unit_price: Decimal.new("100.00"),
              vat_rate: "23"
            }
          ]
        },
        scope
      )

    conn = log_in_user(conn, admin)

    {:ok, view, _html} = live(conn, ~p"/sprzedazowe?szkic_kreatora=#{draft.id}&krok=2")

    selector =
      "button[phx-click='set_price_input_mode'][phx-value-mode='gross'][phx-value-index='0']"

    assert has_element?(view, selector, "123.00")
    refute has_element?(view, selector, "246,00")
    assert has_element?(view, "p.w-28", "23,00")
    refute has_element?(view, "p.w-28", "46,00")
  end

  test "items step can submit gross unit price while storing high-precision net", %{conn: conn} do
    admin = admin_fixture()
    draft = items_step_draft!(admin)
    scope = scope_for(admin)
    conn = log_in_user(conn, admin)

    {:ok, view, _html} = live(conn, ~p"/sprzedazowe?szkic_kreatora=#{draft.id}&krok=2")

    html = render(view)

    assert html =~ "Wartość VAT"
    assert html =~ ~s(name="form[items][0][unit_price]")
    refute html =~ ~s(name="form[items][0][gross_value]")
    assert has_element?(view, "input[type='number'][name='form[items][0][unit_price]']")
    refute has_element?(view, "input[type='number'][name='form[items][0][gross_value]']")

    html =
      view
      |> element("button[phx-click='set_price_input_mode'][phx-value-mode='gross'][phx-value-index='0']")
      |> render_click()

    assert html =~ ~s(name="form[items][0][gross_value]")
    assert html =~ ~s(placeholder="0.00")
    assert html =~ ~s(value="")
    assert has_element?(view, "input[type='number'][name='form[items][0][gross_value]']")
    refute has_element?(view, "input[type='number'][name='form[items][0][unit_price]']")

    html =
      view
      |> form("#invoice-form", %{
        "form" => %{
          "currency" => "PLN",
          "items" => %{
            "0" => %{
              "index" => "0",
              "name" => "Usługa brutto",
              "quantity" => "2",
              "unit" => "szt.",
              "unit_price" => "",
              "gross_value" => "",
              "vat_rate" => "23"
            }
          }
        }
      })
      |> render_change()

    refute html =~ ~s(data-for="gross-price")

    view
    |> form("#invoice-form", %{
      "form" => %{
        "currency" => "PLN",
        "items" => %{
          "0" => %{
            "index" => "0",
            "name" => "Usługa brutto",
            "quantity" => "2",
            "unit" => "szt.",
            "unit_price" => "",
            "gross_value" => "123.00",
            "vat_rate" => "23"
          }
        }
      }
    })
    |> render_submit()

    [item] =
      draft.id |> Invoicing.get_wizard_draft!(load: [:items], scope: scope) |> Map.fetch!(:items)

    refute Decimal.eq?(item.unit_price, Decimal.new("81.30"))

    assert Decimal.eq?(
             Decimal.round(Decimal.mult(item.unit_price, Decimal.new("1.23")), 2),
             Decimal.new("123.00")
           )
  end

  test "items step keeps typed gross line value while required fields are invalid", %{conn: conn} do
    admin = admin_fixture()
    draft = items_step_draft!(admin)
    conn = log_in_user(conn, admin)

    {:ok, view, _html} = live(conn, ~p"/sprzedazowe?szkic_kreatora=#{draft.id}&krok=2")

    view
    |> element("button[phx-click='set_price_input_mode'][phx-value-mode='gross'][phx-value-index='0']")
    |> render_click()

    html =
      view
      |> form("#invoice-form", %{
        "form" => %{
          "currency" => "PLN",
          "items" => %{
            "0" => %{
              "index" => "0",
              "name" => "",
              "quantity" => "",
              "unit" => "szt.",
              "unit_price" => "",
              "gross_value" => "100.00",
              "vat_rate" => "23"
            }
          }
        }
      })
      |> render_change()

    assert html =~ ~s(name="form[items][0][gross_value]")
    assert html =~ ~s(value="100.00")

    view
    |> element("button[phx-click='set_price_input_mode'][phx-value-mode='net'][phx-value-index='0']")
    |> render_click()

    html =
      view
      |> element("button[phx-click='set_price_input_mode'][phx-value-mode='gross'][phx-value-index='0']")
      |> render_click()

    assert html =~ ~s(name="form[items][0][gross_value]")
    assert html =~ ~s(value="100.00")
  end

  test "items step only shows required errors after invalid submit", %{conn: conn} do
    admin = admin_fixture()
    draft = items_step_draft!(admin)
    conn = log_in_user(conn, admin)

    {:ok, view, html} = live(conn, ~p"/sprzedazowe?szkic_kreatora=#{draft.id}&krok=2")

    refute html =~ "jest wymagane"

    html =
      view
      |> form("#invoice-form", %{
        "form" => %{
          "currency" => "PLN",
          "items" => %{
            "0" => %{
              "index" => "0",
              "name" => "",
              "quantity" => "",
              "unit" => "szt.",
              "unit_price" => "",
              "vat_rate" => "23"
            }
          }
        }
      })
      |> render_change()

    refute html =~ "jest wymagane"

    html =
      view
      |> form("#invoice-form", %{
        "form" => %{
          "currency" => "PLN",
          "items" => %{
            "0" => %{
              "index" => "0",
              "name" => "",
              "quantity" => "",
              "unit" => "szt.",
              "unit_price" => "",
              "vat_rate" => "23"
            }
          }
        }
      })
      |> render_submit()

    assert html =~ "jest wymagane"
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

  test "copy route preserves toggles, payment method, derived account, and items while clearing dates",
       %{
         conn: conn
       } do
    admin = admin_fixture()
    scope = scope_for(admin)

    {:ok, default_eur_account} =
      Finances.create_manual_bank_account(
        %{
          iban: "DE02120300000000202020202020",
          name: "EUR default",
          currency: "EUR",
          is_default: true
        },
        scope: scope
      )

    source_invoice =
      sales_invoice_fixture!(admin, %{
        payment_method: :transfer,
        seller_account_number: "DE44123456781234567812",
        invoice_note: "Uwagi dla klienta",
        internal_note: "Notatka wewnętrzna",
        buyer_display_name: "Buyer GmbH Display",
        buyer_email: "billing@example.com",
        buyer_phone: "+49 123 456 789",
        buyer_description: "Abonament roczny",
        is_reverse_charge: true,
        sales_invoice_items: [
          base_item_attrs(%{
            index: 0,
            name: "Usługa A",
            quantity: Decimal.new("2"),
            unit_price: Decimal.new("100.00"),
            vat_rate: "23"
          }),
          base_item_attrs(%{
            index: 1,
            name: "Usługa B",
            quantity: Decimal.new("1.5"),
            unit_price: Decimal.new("250.00"),
            vat_rate: "8"
          })
        ]
      })

    conn = log_in_user(conn, admin)

    {:ok, _view, _html} = live(conn, "/sprzedazowe?skopiuj=#{source_invoice.id}")

    copied_draft = copied_draft!(admin)

    assert InvoicingCopyAssertions.assert_preserved_fields!(source_invoice, copied_draft)
    assert InvoicingCopyAssertions.assert_cleared_dates!(copied_draft)

    assert InvoicingCopyAssertions.assert_derived_seller_account!(
             copied_draft,
             default_eur_account.iban
           )

    assert InvoicingCopyAssertions.assert_line_items_match!(
             source_invoice.sales_invoice_items,
             copied_draft.items
           )
  end

  test "copied invoice renders its Money total in the preview", %{conn: conn} do
    admin = admin_fixture()
    scope = scope_for(admin)

    {:ok, bank_account} =
      Finances.create_manual_bank_account(
        %{
          iban: "DE03120300000000303030303030",
          name: "EUR default",
          currency: "EUR",
          is_default: true
        },
        scope: scope
      )

    source_invoice =
      sales_invoice_fixture!(admin, %{
        sales_invoice_items: [
          base_item_attrs(%{
            name: "Usługa testowa",
            quantity: Decimal.new("1"),
            unit_price: Decimal.new("100.00"),
            vat_rate: "23"
          })
        ]
      })

    conn = log_in_user(conn, admin)
    {:ok, _view, _html} = live(conn, "/sprzedazowe?skopiuj=#{source_invoice.id}")
    copied_draft = copied_draft!(admin)

    {:ok, copied_draft} =
      WizardDraft.update_payment(
        copied_draft,
        %{
          sale_date: ~D[2026-02-01],
          due_date: ~D[2026-02-14],
          payment_method: :transfer,
          seller_account_number: bank_account.iban
        },
        scope: scope
      )

    {:ok, preview, html} =
      live(conn, ~p"/sprzedazowe?szkic_kreatora=#{copied_draft.id}&krok=4")

    assert has_element?(preview, "h1", "Podgląd faktury")
    assert html =~ Money.to_string!(Money.new("EUR", Decimal.new("123.00")))
  end

  test "recent invoices copy repopulates the current draft with matching values", %{conn: conn} do
    admin = admin_fixture()
    scope = scope_for(admin)

    {:ok, default_eur_account} =
      Finances.create_manual_bank_account(
        %{
          iban: "DE55120300000000505050505050",
          name: "EUR default",
          currency: "EUR",
          is_default: true
        },
        scope: scope
      )

    issue_date =
      Date.utc_today()
      |> Map.put(:day, 1)
      |> Date.shift(month: -1, day: 14)

    source_invoice =
      sales_invoice_fixture!(admin, %{
        issue_date: issue_date,
        sale_date: issue_date,
        due_date: Date.add(issue_date, 14),
        payment_method: :transfer,
        seller_account_number: "DE66123456781234567812",
        buyer_display_name: "Buyer GmbH Copy",
        invoice_note: "Skopiowana uwaga",
        internal_note: "Skopiowana notatka",
        sales_invoice_items: [
          base_item_attrs(%{
            index: 0,
            name: "Pakiet Premium",
            quantity: Decimal.new("3"),
            unit_price: Decimal.new("99.99"),
            vat_rate: "23"
          })
        ]
      })

    {:ok, draft} = WizardDraft.create(%{organization_id: admin.organization_id}, scope: scope)
    conn = log_in_user(conn, admin)

    {:ok, view, _html} =
      live(conn, ~p"/sprzedazowe?szkic_kreatora=#{draft.id}&krok=1&karta=ostatnie_faktury")

    view
    |> element("button[phx-click='select_base_invoice'][phx-value-invoice_id='#{source_invoice.id}']")
    |> render_click()

    copied_draft = Invoicing.get_wizard_draft!(draft.id, load: [:items], scope: scope)

    assert InvoicingCopyAssertions.assert_preserved_fields!(source_invoice, copied_draft)
    assert InvoicingCopyAssertions.assert_cleared_dates!(copied_draft)

    assert InvoicingCopyAssertions.assert_derived_seller_account!(
             copied_draft,
             default_eur_account.iban
           )

    assert InvoicingCopyAssertions.assert_line_items_match!(
             source_invoice.sales_invoice_items,
             copied_draft.items
           )
  end

  test "copy with legacy invalid counterparty data opens correction modal and preserves items", %{
    conn: conn
  } do
    admin = admin_fixture()
    legacy_invoice = legacy_invoice_fixture!(admin)
    conn = log_in_user(conn, admin)

    {:ok, _view, html} = live(conn, "/sprzedazowe?skopiuj=#{legacy_invoice.id}")

    copied_draft = copied_draft!(admin)

    assert html =~ "Wprowadź dane kontrahenta"
    assert html =~ "Skopiowano pozycje z faktury, ale dane kontrahenta wymagają poprawy"
    assert copied_draft.step == :counterparty

    assert InvoicingCopyAssertions.assert_line_items_match!(
             legacy_invoice.sales_invoice_items,
             copied_draft.items
           )
  end

  test "copied draft can be confirmed into a new invoice with preserved business fields", %{
    conn: conn
  } do
    admin = admin_fixture()
    scope = scope_for(admin)

    {:ok, default_eur_account} =
      Finances.create_manual_bank_account(
        %{
          iban: "DE77120300000000707070707070",
          name: "EUR default",
          currency: "EUR",
          is_default: true
        },
        scope: scope
      )

    source_invoice =
      sales_invoice_fixture!(admin, %{
        payment_method: :transfer,
        seller_account_number: "DE88123456781234567812",
        invoice_note: "Notatka dla klienta",
        internal_note: "Notatka dla zespołu",
        buyer_display_name: "Byte Buyer",
        sales_invoice_items: [
          base_item_attrs(%{
            index: 0,
            name: "Pakiet Enterprise",
            quantity: Decimal.new("2"),
            unit_price: Decimal.new("500.00"),
            vat_rate: "23"
          })
        ]
      })

    conn = log_in_user(conn, admin)
    {:ok, _view, _html} = live(conn, "/sprzedazowe?skopiuj=#{source_invoice.id}")
    copied_draft = copied_draft!(admin)

    {:ok, copied_draft} =
      WizardDraft.update_payment(
        copied_draft,
        %{
          sale_date: ~D[2026-02-01],
          due_date: ~D[2026-02-14],
          payment_method: :transfer,
          seller_account_number: default_eur_account.iban
        },
        scope: scope
      )

    should_send_emails = false

    {:ok, copied_invoice} =
      SalesInvoice.confirm_from_draft(
        copied_draft.id,
        "FV/COPY/#{System.unique_integer([:positive])}",
        %{name: "Test Organization", address: "ul. Organizacyjna 1, Warszawa", nip: "1234567890"},
        should_send_emails,
        scope: scope
      )

    copied_invoice = Ash.load!(copied_invoice, [:sales_invoice_items], scope: scope)

    assert InvoicingCopyAssertions.assert_preserved_fields!(source_invoice, copied_invoice)

    assert InvoicingCopyAssertions.assert_derived_seller_account!(
             copied_invoice,
             default_eur_account.iban
           )

    assert InvoicingCopyAssertions.assert_line_items_match!(
             source_invoice.sales_invoice_items,
             copied_invoice.sales_invoice_items
           )

    assert copied_invoice.sale_date == ~D[2026-02-01]
    assert copied_invoice.due_date == ~D[2026-02-14]
    assert copied_invoice.invoice_number != source_invoice.invoice_number
  end

  defp scope_for(user), do: %Scope{actor: user, tenant: user.organization_id}

  defp copied_draft!(admin) do
    scope = scope_for(admin)

    scope
    |> then(&Invoicing.list_wizard_drafts!(scope: &1))
    |> List.first()
    |> Ash.load!([:items], scope: scope)
  end

  defp sales_invoice_fixture!(admin, overrides) do
    default_attrs = %{
      invoice_type: :foreign,
      invoice_number: "FV/COPY/#{System.unique_integer([:positive])}",
      sale_date: ~D[2026-01-10],
      issue_date: ~D[2026-01-10],
      due_date: ~D[2026-01-24],
      payment_method: :transfer,
      currency: "EUR",
      seller_nip: "1234567890",
      seller_display_name: "Seller Sp. z o.o.",
      seller_address: "ul. Testowa 1, 00-001 Warszawa",
      seller_account_number: "DE99123456781234567812",
      buyer_type: :company,
      buyer_id: "DE123456789",
      buyer_full_name: "Buyer GmbH",
      buyer_address: "Teststrasse 1, 10115 Berlin",
      buyer_country: "DE",
      ksef_invoice_kind: :vat,
      sales_invoice_items: [base_item_attrs(%{})]
    }

    invoice =
      Invoicing.create_sales_invoice!(Map.merge(default_attrs, overrides),
        scope: scope_for(admin)
      )

    Ash.load!(invoice, [:sales_invoice_items], scope: scope_for(admin))
  end

  defp legacy_invoice_fixture!(admin) do
    invoice =
      Ash.Seed.seed!(SalesInvoice, %{
        invoice_number: "FV/LEGACY/#{System.unique_integer([:positive])}",
        sale_date: ~D[2026-01-10],
        issue_date: ~D[2026-01-10],
        due_date: ~D[2026-01-24],
        payment_method: :transfer,
        currency: "EUR",
        seller_nip: "1234567890",
        seller_display_name: "Seller Sp. z o.o.",
        seller_address: "ul. Testowa 1, 00-001 Warszawa",
        seller_account_number: "DE11123456781234567812",
        buyer_type: :company,
        buyer_id: nil,
        buyer_full_name: "Legacy Buyer GmbH",
        buyer_address: "Legacy Strasse 1",
        buyer_country: "DE",
        organization_id: admin.organization_id,
        ksef_invoice_kind: :vat
      })

    Ash.Seed.seed!(Firmowid.Ash.Invoicing.SalesInvoiceItem, %{
      organization_id: admin.organization_id,
      sales_invoice_id: invoice.id,
      index: 0,
      name: "Legacy item",
      quantity: Decimal.new("1"),
      unit: "szt.",
      unit_price: Decimal.new("100.00"),
      vat_rate: "23"
    })

    Ash.load!(invoice, [:sales_invoice_items], scope: scope_for(admin))
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

  defp base_item_attrs(overrides) do
    Enum.into(overrides, %{
      index: 0,
      name: "Programming service",
      quantity: Decimal.new("1"),
      unit: "szt.",
      unit_price: Decimal.new("100.00"),
      vat_rate: "23"
    })
  end
end
