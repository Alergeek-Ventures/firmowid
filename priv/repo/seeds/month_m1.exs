# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Firmowid.Seeds.MonthM1 do
  @moduledoc """
  Seeds for M-1 (1 month ago) — fully matched & tagged.

  Revenue:
    GhostPet    50h × $170 = $8,500 (USD)   → project:GhostPet
    FlatMate    30h × £112 = £3,360 (GBP)    → project:FlatMate
    TacoOverflow 45h × €130 = €5,850 (EUR)   → project:TacoOverflow

  Costs:
    OVH Cloud hosting     -2,400 PLN  → project:Firmowid
    OpenCode Zen           -€120 EUR  → :company
    Regus office rent     -4,500 PLN  → :company
    Biuro Plus supplies     -380 PLN  → untagged
    ING bank fee             -25 PLN  → :company

  Wages (skip_invoicing, :company):
    Kira Voss       -4,500 PLN (30h × 150 PLN/h)
    Tomek Briar     -4,560 PLN (38h × 120 PLN/h)
    Sable Orin      -1,600 PLN (16h × 100 PLN/h)
    Jules Kadar     -3,250 PLN (25h × 130 PLN/h)
    Maren Solke     -3,300 PLN (30h × 110 PLN/h)

  THB:
    Outgoing conversion   -50,000 THB → :internal (skip_invoicing)
    PLN side of conv.     +4,750 PLN  → :internal (skip_invoicing)
  """

  alias Firmowid.Ash.Analysis.EntityTag
  alias Firmowid.CostInvoices
  alias Firmowid.Repo
  alias Firmowid.SalesInvoices
  alias Firmowid.Seeds.Helpers

  def seed!(ctx) do
    %{bytecraft: bytecraft, bank_accounts: banks, projects: projects, counterparties: cps} = ctx

    sale_date = Helpers.date_months_ago(1, 15)
    issue_date = Helpers.date_months_ago(1, 16)
    due_date = Helpers.date_months_ago(1, 28)
    booking = Helpers.date_months_ago(1, 20)
    prefix = Helpers.month_prefix(1)

    # — Revenue transactions —

    txn_ghostpet =
      Helpers.get_or_insert_txn("m1_sale_ghostpet", bytecraft.id, %{
        creditor_name: "Bytecraft Collective sp. z o.o.",
        creditor_account: "PL42105000997603123456789014",
        debtor_name: "GhostPet Inc.",
        debtor_account: "N/A",
        transaction_amount: 8_500.00,
        transaction_currency: "USD",
        booking_date: booking,
        bank_account_id: banks.usd.id,
        skip_invoicing: false,
        remittance_information_unstructured: "Faktura BC/01/#{prefix} — GhostPet moduł papugi i AI wsparcia w żałobie"
      })

    txn_flatmate =
      Helpers.get_or_insert_txn("m1_sale_flatmate", bytecraft.id, %{
        creditor_name: "Bytecraft Collective sp. z o.o.",
        creditor_account: "PL19105000997603123456789015",
        debtor_name: "FlatEarth Dating Ltd.",
        debtor_account: "N/A",
        transaction_amount: 3_360.00,
        transaction_currency: "GBP",
        booking_date: booking,
        bank_account_id: banks.gbp.id,
        skip_invoicing: false,
        remittance_information_unstructured: "Faktura BC/02/#{prefix} — FlatMate system powiadomień na krawędzi dysku"
      })

    txn_taco =
      Helpers.get_or_insert_txn("m1_sale_taco", bytecraft.id, %{
        creditor_name: "Bytecraft Collective sp. z o.o.",
        creditor_account: "PL85105000997603123456789013",
        debtor_name: "TacoOverflow Inc.",
        debtor_account: "DE89370400440532013000",
        transaction_amount: 5_850.00,
        transaction_currency: "EUR",
        booking_date: booking,
        bank_account_id: banks.eur.id,
        skip_invoicing: false,
        remittance_information_unstructured: "Faktura BC/03/#{prefix} — TacoOverflow system odznak ostrości"
      })

    # — Cost transactions —

    txn_ovh =
      Helpers.get_or_insert_txn("m1_cost_ovh", bytecraft.id, %{
        creditor_name: "OVH Cloud Sp. z o.o.",
        creditor_account: "PL50102013300000210201234567",
        debtor_name: "Bytecraft Collective sp. z o.o.",
        debtor_account: "PL61105000997603123456789012",
        transaction_amount: -2_400.00,
        transaction_currency: "PLN",
        booking_date: Helpers.date_months_ago(1, 5),
        bank_account_id: banks.pln.id,
        skip_invoicing: false,
        remittance_information_unstructured: "OVH Cloud — serwery dedykowane"
      })

    txn_opencode =
      Helpers.get_or_insert_txn("m1_cost_opencode", bytecraft.id, %{
        creditor_name: "OpenCode GmbH",
        creditor_account: "DE44500105175407324931",
        debtor_name: "Bytecraft Collective sp. z o.o.",
        debtor_account: "PL85105000997603123456789013",
        transaction_amount: -120.00,
        transaction_currency: "EUR",
        booking_date: Helpers.date_months_ago(1, 7),
        bank_account_id: banks.eur.id,
        skip_invoicing: false,
        remittance_information_unstructured: "OpenCode Zen — asystent AI do programowania, plan zespołowy"
      })

    txn_rent =
      Helpers.get_or_insert_txn("m1_cost_rent", bytecraft.id, %{
        creditor_name: "Regus Business Centre Sp. z o.o.",
        creditor_account: "PL15109024020000000134672891",
        debtor_name: "Bytecraft Collective sp. z o.o.",
        debtor_account: "PL61105000997603123456789012",
        transaction_amount: -4_500.00,
        transaction_currency: "PLN",
        booking_date: Helpers.date_months_ago(1, 1),
        bank_account_id: banks.pln.id,
        skip_invoicing: false,
        remittance_information_unstructured: "Regus — wynajem biura"
      })

    txn_biuro =
      Helpers.get_or_insert_txn("m1_cost_biuro", bytecraft.id, %{
        creditor_name: "Biuro Plus Sp. z o.o.",
        creditor_account: "PL88109024020000000139876543",
        debtor_name: "Bytecraft Collective sp. z o.o.",
        debtor_account: "PL61105000997603123456789012",
        transaction_amount: -380.00,
        transaction_currency: "PLN",
        booking_date: Helpers.date_months_ago(1, 12),
        bank_account_id: banks.pln.id,
        skip_invoicing: false,
        remittance_information_unstructured: "Biuro Plus — papier, tonery, materiały biurowe"
      })

    txn_bankfee =
      Helpers.get_or_insert_txn("m1_cost_bankfee", bytecraft.id, %{
        creditor_name: "ING Bank Śląski S.A.",
        creditor_account: "INTERNAL",
        debtor_name: "Bytecraft Collective sp. z o.o.",
        debtor_account: "PL61105000997603123456789012",
        transaction_amount: -25.00,
        transaction_currency: "PLN",
        booking_date: Helpers.date_months_ago(1, 1),
        bank_account_id: banks.pln.id,
        skip_invoicing: true,
        remittance_information_unstructured: "Opłata za prowadzenie rachunku"
      })

    # — THB transactions —

    txn_thb_out =
      Helpers.get_or_insert_txn("m1_thb_conversion_out", bytecraft.id, %{
        creditor_name: "Bank Millennium S.A.",
        creditor_account: "INTERNAL",
        debtor_name: "Bytecraft Collective sp. z o.o.",
        debtor_account: "PL73116022020000000512345678",
        transaction_amount: -50_000.00,
        transaction_currency: "THB",
        booking_date: Helpers.date_months_ago(1, 10),
        bank_account_id: banks.thb.id,
        skip_invoicing: true,
        remittance_information_unstructured: "Przewalutowanie THB → PLN, kurs 0.095"
      })

    txn_thb_pln =
      Helpers.get_or_insert_txn("m1_thb_conversion_pln", bytecraft.id, %{
        creditor_name: "Bytecraft Collective sp. z o.o.",
        creditor_account: "PL61105000997603123456789012",
        debtor_name: "Bank Millennium S.A.",
        debtor_account: "INTERNAL",
        transaction_amount: 4_750.00,
        transaction_currency: "PLN",
        booking_date: Helpers.date_months_ago(1, 10),
        bank_account_id: banks.pln.id,
        skip_invoicing: true,
        remittance_information_unstructured: "Wpływ z przewalutowania THB → PLN (50,000 THB)"
      })

    # — Wage payment transactions (skip_invoicing — no invoice for salaries) —

    wage_booking = Helpers.date_months_ago(1, 28)

    txn_wage_kira =
      Helpers.get_or_insert_txn("m1_wage_kira", bytecraft.id, %{
        creditor_name: "Kira Voss",
        creditor_account: "PL11109024020000000187654321",
        debtor_name: "Bytecraft Collective sp. z o.o.",
        debtor_account: "PL61105000997603123456789012",
        transaction_amount: -4_500.00,
        transaction_currency: "PLN",
        booking_date: wage_booking,
        bank_account_id: banks.pln.id,
        skip_invoicing: true,
        remittance_information_unstructured: "Wynagrodzenie — Kira Voss, #{prefix}"
      })

    txn_wage_tomek =
      Helpers.get_or_insert_txn("m1_wage_tomek", bytecraft.id, %{
        creditor_name: "Tomek Briar",
        creditor_account: "PL22109024020000000198765432",
        debtor_name: "Bytecraft Collective sp. z o.o.",
        debtor_account: "PL61105000997603123456789012",
        transaction_amount: -4_560.00,
        transaction_currency: "PLN",
        booking_date: wage_booking,
        bank_account_id: banks.pln.id,
        skip_invoicing: true,
        remittance_information_unstructured: "Wynagrodzenie — Tomek Briar, #{prefix}"
      })

    txn_wage_sable =
      Helpers.get_or_insert_txn("m1_wage_sable", bytecraft.id, %{
        creditor_name: "Sable Orin",
        creditor_account: "PL33109024020000000209876543",
        debtor_name: "Bytecraft Collective sp. z o.o.",
        debtor_account: "PL61105000997603123456789012",
        transaction_amount: -1_600.00,
        transaction_currency: "PLN",
        booking_date: wage_booking,
        bank_account_id: banks.pln.id,
        skip_invoicing: true,
        remittance_information_unstructured: "Wynagrodzenie — Sable Orin, #{prefix}"
      })

    txn_wage_jules =
      Helpers.get_or_insert_txn("m1_wage_jules", bytecraft.id, %{
        creditor_name: "Jules Kadar",
        creditor_account: "PL44109024020000000210987654",
        debtor_name: "Bytecraft Collective sp. z o.o.",
        debtor_account: "PL61105000997603123456789012",
        transaction_amount: -3_250.00,
        transaction_currency: "PLN",
        booking_date: wage_booking,
        bank_account_id: banks.pln.id,
        skip_invoicing: true,
        remittance_information_unstructured: "Wynagrodzenie — Jules Kadar, #{prefix}"
      })

    txn_wage_maren =
      Helpers.get_or_insert_txn("m1_wage_maren", bytecraft.id, %{
        creditor_name: "Maren Solke",
        creditor_account: "PL55109024020000000221098765",
        debtor_name: "Bytecraft Collective sp. z o.o.",
        debtor_account: "PL61105000997603123456789012",
        transaction_amount: -3_300.00,
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
            "name" => "GhostPet moduł papugi — silnik rozmów nawiedzonych",
            "quantity" => 50,
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
            "name" => "FlatMate system powiadomień na krawędzi dysku i udostępnianie lokalizacji",
            "quantity" => 30,
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
            "name" => "TacoOverflow system odznak ostrości i przygotowanie do Serii A",
            "quantity" => 45,
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

    cost_opencode =
      Helpers.get_or_create_cost_invoice("OC/#{prefix}", bytecraft.id, %{
        seller: "OpenCode GmbH",
        seller_display_name: "OpenCode",
        seller_address: "Invalidenstraße 115, 10115 Berlin",
        sale_date: sale_date,
        issue_date: issue_date,
        due_date: due_date,
        total_amount: -120.00,
        currency: "EUR",
        description: "OpenCode Zen — asystent AI do programowania, plan zespołowy, 5 stanowisk",
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

    cost_biuro =
      Helpers.get_or_create_cost_invoice("BP/#{prefix}", bytecraft.id, %{
        seller: "Biuro Plus Sp. z o.o.",
        seller_display_name: "Biuro Plus",
        seller_address: "ul. Biurowa 10, 31-200 Kraków",
        sale_date: sale_date,
        issue_date: issue_date,
        due_date: due_date,
        total_amount: -380.00,
        currency: "PLN",
        description: "Artykuły biurowe: papier A4, tonery HP, materiały eksploatacyjne",
        skip_invoicing: false
      })

    # — Matching —

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
      cost_opencode.id,
      txn_opencode.id,
      bytecraft.id
    )

    CostInvoices.create_cost_invoices_transactions_connection(
      cost_rent.id,
      txn_rent.id,
      bytecraft.id
    )

    CostInvoices.create_cost_invoices_transactions_connection(
      cost_biuro.id,
      txn_biuro.id,
      bytecraft.id
    )

    # — Tagging —
    scope = seed_scope()

    # Revenue → project tags
    tag_project!(:sales_invoice, sale_ghostpet.id, [projects.ghostpet.tag_definition_id], scope)
    tag_project!(:sales_invoice, sale_flatmate.id, [projects.flatmate.tag_definition_id], scope)
    tag_project!(:sales_invoice, sale_taco.id, [projects.taco.tag_definition_id], scope)

    # Costs → mixed tags
    tag_project!(:cost_invoice, cost_ovh.id, [projects.firmowid.tag_definition_id], scope)
    tag_category!(:cost_invoice, cost_opencode.id, :company, scope)
    tag_category!(:cost_invoice, cost_rent.id, :company, scope)
    # cost_biuro intentionally untagged

    # Bank fee → :company
    tag_category!(:transaction, txn_bankfee.id, :company, scope)

    # THB → :internal
    tag_category!(:transaction, txn_thb_out.id, :internal, scope)
    tag_category!(:transaction, txn_thb_pln.id, :internal, scope)

    # Wages → project tags (all projects person worked on)
    tag_project!(
      :transaction,
      txn_wage_kira.id,
      [projects.firmowid.tag_definition_id, projects.flatmate.tag_definition_id],
      scope
    )

    tag_project!(
      :transaction,
      txn_wage_tomek.id,
      [projects.firmowid.tag_definition_id, projects.ghostpet.tag_definition_id, projects.taco.tag_definition_id],
      scope
    )

    tag_project!(:transaction, txn_wage_sable.id, [projects.flatmate.tag_definition_id], scope)
    tag_project!(:transaction, txn_wage_jules.id, [projects.taco.tag_definition_id], scope)

    tag_project!(
      :transaction,
      txn_wage_maren.id,
      [projects.ghostpet.tag_definition_id, projects.taco.tag_definition_id],
      scope
    )
  end

  defp tag_category!(entity_type, resource_id, kind, scope) do
    EntityTag.set_entity_category!(
      %{entity_type: entity_type, resource_id: resource_id, kind: kind},
      scope: scope
    )
  end

  defp tag_project!(entity_type, resource_id, tag_definition_ids, scope) do
    EntityTag.set_entity_project_tags!(
      %{entity_type: entity_type, resource_id: resource_id, tag_definition_ids: tag_definition_ids},
      scope: scope
    )
  end

  defp seed_scope do
    %Firmowid.Ash.Scope{
      current_user: %{id: "00000000-0000-0000-0000-000000000000", role: :admin},
      current_tenant: Repo.get_org_id()
    }
  end
end
