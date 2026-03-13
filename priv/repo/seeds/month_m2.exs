# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Firmowid.Seeds.MonthM2 do
  @moduledoc """
  Seeds for M-2 (2 months ago) — fully matched & tagged.

  Revenue:
    GhostPet    35h × $170 = $5,950 (USD)   → project:GhostPet
    FlatMate    40h × £112 = £4,480 (GBP)    → project:FlatMate
    TacoOverflow 60h × €130 = €7,800 (EUR)   → project:TacoOverflow

  Costs:
    OVH Cloud hosting     -2,400 PLN  → project:Firmowid
    GitHub Actions+Copilot  -$250 USD → :company
    Regus office rent     -4,500 PLN  → :company
    Apple laptops (3×)   -18,000 PLN  → :company
    Dell monitors (3×)    -4,500 PLN  → untagged

  Wages (skip_invoicing, :company):
    Kira Voss       -4,800 PLN (32h × 150 PLN/h)
    Tomek Briar     -4,320 PLN (36h × 120 PLN/h)
    Sable Orin      -1,800 PLN (18h × 100 PLN/h)
    Jules Kadar     -3,510 PLN (27h × 130 PLN/h)
    Maren Solke     -3,080 PLN (28h × 110 PLN/h)

  THB:
    Incoming freelance   +150,000 THB → :internal (skip_invoicing)
    Outgoing conversion   -50,000 THB → :internal (skip_invoicing)
    PLN side of conv.     +4,800 PLN  → :internal (skip_invoicing)
  """

  alias Firmowid.Analysis
  alias Firmowid.CostInvoices
  alias Firmowid.SalesInvoices
  alias Firmowid.Seeds.Helpers

  def seed!(ctx) do
    %{bytecraft: bytecraft, bank_accounts: banks, projects: projects, counterparties: cps} = ctx

    sale_date = Helpers.date_months_ago(2, 10)
    issue_date = Helpers.date_months_ago(2, 11)
    due_date = Helpers.date_months_ago(2, 25)
    booking = Helpers.date_months_ago(2, 15)
    prefix = Helpers.month_prefix(2)

    # — Revenue transactions —

    txn_ghostpet =
      Helpers.get_or_insert_txn("m2_sale_ghostpet", bytecraft.id, %{
        creditor_name: "Bytecraft Collective sp. z o.o.",
        creditor_account: "PL42105000997603123456789014",
        debtor_name: "GhostPet Inc.",
        debtor_account: "N/A",
        transaction_amount: 5_950.00,
        transaction_currency: "USD",
        booking_date: booking,
        bank_account_id: banks.usd.id,
        skip_invoicing: false,
        remittance_information_unstructured: "Faktura BC/01/#{prefix} — platforma rozmów AI z pupilami"
      })

    txn_flatmate =
      Helpers.get_or_insert_txn("m2_sale_flatmate", bytecraft.id, %{
        creditor_name: "Bytecraft Collective sp. z o.o.",
        creditor_account: "PL19105000997603123456789015",
        debtor_name: "FlatEarth Dating Ltd.",
        debtor_account: "N/A",
        transaction_amount: 4_480.00,
        transaction_currency: "GBP",
        booking_date: booking,
        bank_account_id: banks.gbp.id,
        skip_invoicing: false,
        remittance_information_unstructured: "Faktura BC/02/#{prefix} — FlatMate mapa dysku i silnik dopasowań"
      })

    txn_taco =
      Helpers.get_or_insert_txn("m2_sale_taco", bytecraft.id, %{
        creditor_name: "Bytecraft Collective sp. z o.o.",
        creditor_account: "PL85105000997603123456789013",
        debtor_name: "TacoOverflow Inc.",
        debtor_account: "DE89370400440532013000",
        transaction_amount: 7_800.00,
        transaction_currency: "EUR",
        booking_date: booking,
        bank_account_id: banks.eur.id,
        skip_invoicing: false,
        remittance_information_unstructured: "Faktura BC/03/#{prefix} — TacoOverflow silnik oceny ostrości i wdrożenie"
      })

    # — Cost transactions —

    txn_ovh =
      Helpers.get_or_insert_txn("m2_cost_ovh", bytecraft.id, %{
        creditor_name: "OVH Cloud Sp. z o.o.",
        creditor_account: "PL50102013300000210201234567",
        debtor_name: "Bytecraft Collective sp. z o.o.",
        debtor_account: "PL61105000997603123456789012",
        transaction_amount: -2_400.00,
        transaction_currency: "PLN",
        booking_date: Helpers.date_months_ago(2, 5),
        bank_account_id: banks.pln.id,
        skip_invoicing: false,
        remittance_information_unstructured: "OVH Cloud — serwery dedykowane, środowisko produkcyjne"
      })

    txn_github =
      Helpers.get_or_insert_txn("m2_cost_github", bytecraft.id, %{
        creditor_name: "GitHub, Inc.",
        creditor_account: "N/A",
        debtor_name: "Bytecraft Collective sp. z o.o.",
        debtor_account: "PL42105000997603123456789014",
        transaction_amount: -250.00,
        transaction_currency: "USD",
        booking_date: Helpers.date_months_ago(2, 3),
        bank_account_id: banks.usd.id,
        skip_invoicing: false,
        remittance_information_unstructured: "GitHub Actions CI/CD + Copilot Business — 5 stanowisk"
      })

    txn_rent =
      Helpers.get_or_insert_txn("m2_cost_rent", bytecraft.id, %{
        creditor_name: "Regus Business Centre Sp. z o.o.",
        creditor_account: "PL15109024020000000134672891",
        debtor_name: "Bytecraft Collective sp. z o.o.",
        debtor_account: "PL61105000997603123456789012",
        transaction_amount: -4_500.00,
        transaction_currency: "PLN",
        booking_date: Helpers.date_months_ago(2, 1),
        bank_account_id: banks.pln.id,
        skip_invoicing: false,
        remittance_information_unstructured: "Regus — wynajem biura, ul. Marszałkowska 11/4"
      })

    txn_laptops =
      Helpers.get_or_insert_txn("m2_cost_laptops", bytecraft.id, %{
        creditor_name: "Apple Polska Sp. z o.o.",
        creditor_account: "PL68109024020000000130567892",
        debtor_name: "Bytecraft Collective sp. z o.o.",
        debtor_account: "PL61105000997603123456789012",
        transaction_amount: -18_000.00,
        transaction_currency: "PLN",
        booking_date: Helpers.date_months_ago(2, 8),
        bank_account_id: banks.pln.id,
        skip_invoicing: false,
        remittance_information_unstructured: "Apple MacBook Pro 14\" M3 Pro × 3 szt."
      })

    txn_monitors =
      Helpers.get_or_insert_txn("m2_cost_monitors", bytecraft.id, %{
        creditor_name: "Dell Technologies Sp. z o.o.",
        creditor_account: "PL22109024020000000131987654",
        debtor_name: "Bytecraft Collective sp. z o.o.",
        debtor_account: "PL61105000997603123456789012",
        transaction_amount: -4_500.00,
        transaction_currency: "PLN",
        booking_date: Helpers.date_months_ago(2, 12),
        bank_account_id: banks.pln.id,
        skip_invoicing: false,
        remittance_information_unstructured: "Dell U2723QE 4K × 3 szt."
      })

    # — THB transactions (all skip_invoicing) —

    txn_thb_in =
      Helpers.get_or_insert_txn("m2_thb_freelance_in", bytecraft.id, %{
        creditor_name: "Bytecraft Collective sp. z o.o.",
        creditor_account: "PL73116022020000000512345678",
        debtor_name: "Siam Digital Co., Ltd.",
        debtor_account: "TH0212345678901234567890",
        transaction_amount: 150_000.00,
        transaction_currency: "THB",
        booking_date: Helpers.date_months_ago(2, 7),
        bank_account_id: banks.thb.id,
        skip_invoicing: true,
        remittance_information_unstructured: "Wpłata freelance — Jules Kadar, projekt tajskiego startupu"
      })

    txn_thb_out =
      Helpers.get_or_insert_txn("m2_thb_conversion_out", bytecraft.id, %{
        creditor_name: "Bank Millennium S.A.",
        creditor_account: "INTERNAL",
        debtor_name: "Bytecraft Collective sp. z o.o.",
        debtor_account: "PL73116022020000000512345678",
        transaction_amount: -50_000.00,
        transaction_currency: "THB",
        booking_date: Helpers.date_months_ago(2, 9),
        bank_account_id: banks.thb.id,
        skip_invoicing: true,
        remittance_information_unstructured: "Przewalutowanie THB → PLN, kurs 0.096"
      })

    txn_thb_pln =
      Helpers.get_or_insert_txn("m2_thb_conversion_pln", bytecraft.id, %{
        creditor_name: "Bytecraft Collective sp. z o.o.",
        creditor_account: "PL61105000997603123456789012",
        debtor_name: "Bank Millennium S.A.",
        debtor_account: "INTERNAL",
        transaction_amount: 4_800.00,
        transaction_currency: "PLN",
        booking_date: Helpers.date_months_ago(2, 9),
        bank_account_id: banks.pln.id,
        skip_invoicing: true,
        remittance_information_unstructured: "Wpływ z przewalutowania THB → PLN (50,000 THB)"
      })

    # — Wage payment transactions (skip_invoicing — no invoice for salaries) —

    wage_booking = Helpers.date_months_ago(2, 28)

    txn_wage_kira =
      Helpers.get_or_insert_txn("m2_wage_kira", bytecraft.id, %{
        creditor_name: "Kira Voss",
        creditor_account: "PL11109024020000000187654321",
        debtor_name: "Bytecraft Collective sp. z o.o.",
        debtor_account: "PL61105000997603123456789012",
        transaction_amount: -4_800.00,
        transaction_currency: "PLN",
        booking_date: wage_booking,
        bank_account_id: banks.pln.id,
        skip_invoicing: true,
        remittance_information_unstructured: "Wynagrodzenie — Kira Voss, #{prefix}"
      })

    txn_wage_tomek =
      Helpers.get_or_insert_txn("m2_wage_tomek", bytecraft.id, %{
        creditor_name: "Tomek Briar",
        creditor_account: "PL22109024020000000198765432",
        debtor_name: "Bytecraft Collective sp. z o.o.",
        debtor_account: "PL61105000997603123456789012",
        transaction_amount: -4_320.00,
        transaction_currency: "PLN",
        booking_date: wage_booking,
        bank_account_id: banks.pln.id,
        skip_invoicing: true,
        remittance_information_unstructured: "Wynagrodzenie — Tomek Briar, #{prefix}"
      })

    txn_wage_sable =
      Helpers.get_or_insert_txn("m2_wage_sable", bytecraft.id, %{
        creditor_name: "Sable Orin",
        creditor_account: "PL33109024020000000209876543",
        debtor_name: "Bytecraft Collective sp. z o.o.",
        debtor_account: "PL61105000997603123456789012",
        transaction_amount: -1_800.00,
        transaction_currency: "PLN",
        booking_date: wage_booking,
        bank_account_id: banks.pln.id,
        skip_invoicing: true,
        remittance_information_unstructured: "Wynagrodzenie — Sable Orin, #{prefix}"
      })

    txn_wage_jules =
      Helpers.get_or_insert_txn("m2_wage_jules", bytecraft.id, %{
        creditor_name: "Jules Kadar",
        creditor_account: "PL44109024020000000210987654",
        debtor_name: "Bytecraft Collective sp. z o.o.",
        debtor_account: "PL61105000997603123456789012",
        transaction_amount: -3_510.00,
        transaction_currency: "PLN",
        booking_date: wage_booking,
        bank_account_id: banks.pln.id,
        skip_invoicing: true,
        remittance_information_unstructured: "Wynagrodzenie — Jules Kadar, #{prefix}"
      })

    txn_wage_maren =
      Helpers.get_or_insert_txn("m2_wage_maren", bytecraft.id, %{
        creditor_name: "Maren Solke",
        creditor_account: "PL55109024020000000221098765",
        debtor_name: "Bytecraft Collective sp. z o.o.",
        debtor_account: "PL61105000997603123456789012",
        transaction_amount: -3_080.00,
        transaction_currency: "PLN",
        booking_date: wage_booking,
        bank_account_id: banks.pln.id,
        skip_invoicing: true,
        remittance_information_unstructured: "Wynagrodzenie — Maren Solke, #{prefix}"
      })

    # — Sales invoices —

    sale_ghostpet =
      Helpers.get_or_create_sales_invoice("BC/01/#{prefix}", bytecraft.id, %{
        "invoice_type" => "foreign",
        "issue_date" => issue_date,
        "sale_date" => sale_date,
        "due_date" => due_date,
        "currency" => "USD",
        "buyer_display_name" => "GhostPet Inc.",
        "buyer_full_name" => "GhostPet Inc.",
        "buyer_address" => "440 N Barranca Ave #7658, Covina, CA 91723",
        "buyer_country" => "US",
        "buyer_id" => "US-EIN-47-8830291",
        "buyer_type" => "company",
        "payment_method" => "transfer",
        "is_reverse_charge" => false,
        "is_cash_account" => false,
        "counterparty_id" => cps.ghostpet.id,
        "sales_invoice_items" => [
          %{
            "name" => "Platforma rozmów AI z pupilami — rozwój i utrzymanie",
            "quantity" => 35,
            "unit" => "godz.",
            "unit_price" => 170.00,
            "vat_rate" => "np I"
          }
        ]
      })

    sale_flatmate =
      Helpers.get_or_create_sales_invoice("BC/02/#{prefix}", bytecraft.id, %{
        "invoice_type" => "foreign",
        "issue_date" => issue_date,
        "sale_date" => sale_date,
        "due_date" => due_date,
        "currency" => "GBP",
        "buyer_display_name" => "FlatMate",
        "buyer_full_name" => "FlatEarth Dating Ltd.",
        "buyer_address" => "17 Fictitious Lane, London EC2A 4NE",
        "buyer_country" => "GB",
        "buyer_type" => "company",
        "payment_method" => "transfer",
        "is_reverse_charge" => true,
        "is_cash_account" => false,
        "counterparty_id" => cps.flatearth.id,
        "sales_invoice_items" => [
          %{
            "name" => "FlatMate mapa dysku i algorytm dopasowań — sprint 7-8",
            "quantity" => 40,
            "unit" => "godz.",
            "unit_price" => 112.00,
            "vat_rate" => "oo"
          }
        ]
      })

    sale_taco =
      Helpers.get_or_create_sales_invoice("BC/03/#{prefix}", bytecraft.id, %{
        "invoice_type" => "foreign",
        "issue_date" => issue_date,
        "sale_date" => sale_date,
        "due_date" => due_date,
        "currency" => "EUR",
        "buyer_display_name" => "TacoOverflow",
        "buyer_full_name" => "TacoOverflow Inc.",
        "buyer_address" => "Friedrichstraße 123, 10117 Berlin",
        "buyer_country" => "DE",
        "buyer_id" => "DE317256842",
        "buyer_type" => "company",
        "payment_method" => "transfer",
        "is_reverse_charge" => true,
        "is_cash_account" => false,
        "counterparty_id" => cps.taco.id,
        "sales_invoice_items" => [
          %{
            "name" => "TacoOverflow silnik oceny ostrości i wdrożenie na Raspberry Pi",
            "quantity" => 60,
            "unit" => "godz.",
            "unit_price" => 130.00,
            "vat_rate" => "oo"
          }
        ]
      })

    # — Cost invoices —

    cost_ovh =
      Helpers.get_or_create_cost_invoice("OVH/#{prefix}", bytecraft.id, %{
        seller: "OVH Cloud Sp. z o.o.",
        seller_display_name: "OVH Cloud",
        seller_address: "ul. Swobodna 1, 50-088 Wrocław",
        sale_date: sale_date,
        issue_date: issue_date,
        due_date: due_date,
        total_amount: -2_400.00,
        currency: "PLN",
        description: "Serwery dedykowane — środowisko produkcyjne + staging",
        skip_invoicing: false
      })

    cost_github =
      Helpers.get_or_create_cost_invoice("GH/#{prefix}", bytecraft.id, %{
        seller: "GitHub, Inc.",
        seller_display_name: "GitHub",
        seller_address: "88 Colin P Kelly Jr St, San Francisco, CA 94107",
        sale_date: sale_date,
        issue_date: issue_date,
        due_date: due_date,
        total_amount: -250.00,
        currency: "USD",
        description: "GitHub Actions CI/CD minuty + Copilot Business — 5 stanowisk",
        skip_invoicing: false
      })

    cost_rent =
      Helpers.get_or_create_cost_invoice("REG/#{prefix}", bytecraft.id, %{
        seller: "Regus Business Centre Sp. z o.o.",
        seller_display_name: "Regus",
        seller_address: "ul. Marszałkowska 11, 00-624 Warszawa",
        sale_date: sale_date,
        issue_date: issue_date,
        due_date: due_date,
        total_amount: -4_500.00,
        currency: "PLN",
        description: "Wynajem biura — open space + sala konferencyjna",
        skip_invoicing: false
      })

    cost_laptops =
      Helpers.get_or_create_cost_invoice("APL/#{prefix}", bytecraft.id, %{
        seller: "Apple Polska Sp. z o.o.",
        seller_display_name: "Apple",
        seller_address: "ul. Emilii Plater 53, 00-113 Warszawa",
        sale_date: Helpers.date_months_ago(2, 8),
        issue_date: Helpers.date_months_ago(2, 8),
        due_date: Helpers.date_months_ago(2, 22),
        total_amount: -18_000.00,
        currency: "PLN",
        description: "MacBook Pro 14\" M3 Pro × 3 szt. — onboarding nowych pracowników",
        skip_invoicing: false
      })

    cost_monitors =
      Helpers.get_or_create_cost_invoice("DELL/#{prefix}", bytecraft.id, %{
        seller: "Dell Technologies Sp. z o.o.",
        seller_display_name: "Dell",
        seller_address: "ul. Domaniewska 39A, 02-672 Warszawa",
        sale_date: Helpers.date_months_ago(2, 12),
        issue_date: Helpers.date_months_ago(2, 12),
        due_date: Helpers.date_months_ago(2, 26),
        total_amount: -4_500.00,
        currency: "PLN",
        description: "Dell U2723QE 27\" 4K USB-C × 3 szt.",
        skip_invoicing: false
      })

    # — Matching (invoice ↔ transaction) —

    SalesInvoices.create_sales_invoices_transactions_connection(
      sale_ghostpet.id,
      txn_ghostpet.id,
      bytecraft.id
    )

    SalesInvoices.create_sales_invoices_transactions_connection(
      sale_flatmate.id,
      txn_flatmate.id,
      bytecraft.id
    )

    SalesInvoices.create_sales_invoices_transactions_connection(
      sale_taco.id,
      txn_taco.id,
      bytecraft.id
    )

    CostInvoices.create_cost_invoices_transactions_connection(
      cost_ovh.id,
      txn_ovh.id,
      bytecraft.id
    )

    CostInvoices.create_cost_invoices_transactions_connection(
      cost_github.id,
      txn_github.id,
      bytecraft.id
    )

    CostInvoices.create_cost_invoices_transactions_connection(
      cost_rent.id,
      txn_rent.id,
      bytecraft.id
    )

    CostInvoices.create_cost_invoices_transactions_connection(
      cost_laptops.id,
      txn_laptops.id,
      bytecraft.id
    )

    CostInvoices.create_cost_invoices_transactions_connection(
      cost_monitors.id,
      txn_monitors.id,
      bytecraft.id
    )

    # — Tagging —

    # Revenue → project tags
    Analysis.set_entity_project_tags(:sales_invoice, sale_ghostpet.id, [
      projects.ghostpet.tag_definition_id
    ])

    Analysis.set_entity_project_tags(:sales_invoice, sale_flatmate.id, [
      projects.flatmate.tag_definition_id
    ])

    Analysis.set_entity_project_tags(:sales_invoice, sale_taco.id, [
      projects.taco.tag_definition_id
    ])

    # Costs → mixed tags
    Analysis.set_entity_project_tags(:cost_invoice, cost_ovh.id, [
      projects.firmowid.tag_definition_id
    ])

    Analysis.set_entity_category(:cost_invoice, cost_github.id, :company)
    Analysis.set_entity_category(:cost_invoice, cost_rent.id, :company)
    Analysis.set_entity_category(:cost_invoice, cost_laptops.id, :company)
    # cost_monitors intentionally untagged

    # THB → :internal (skip_invoicing transactions tagged directly)
    Analysis.set_entity_category(:transaction, txn_thb_in.id, :internal)
    Analysis.set_entity_category(:transaction, txn_thb_out.id, :internal)
    Analysis.set_entity_category(:transaction, txn_thb_pln.id, :internal)

    # Wages → project tags (all projects person worked on)
    Analysis.set_entity_project_tags(:transaction, txn_wage_kira.id, [
      projects.firmowid.tag_definition_id,
      projects.flatmate.tag_definition_id
    ])

    Analysis.set_entity_project_tags(:transaction, txn_wage_tomek.id, [
      projects.firmowid.tag_definition_id,
      projects.ghostpet.tag_definition_id,
      projects.taco.tag_definition_id
    ])

    Analysis.set_entity_project_tags(:transaction, txn_wage_sable.id, [
      projects.flatmate.tag_definition_id
    ])

    Analysis.set_entity_project_tags(:transaction, txn_wage_jules.id, [
      projects.taco.tag_definition_id
    ])

    Analysis.set_entity_project_tags(:transaction, txn_wage_maren.id, [
      projects.ghostpet.tag_definition_id,
      projects.taco.tag_definition_id
    ])
  end
end
