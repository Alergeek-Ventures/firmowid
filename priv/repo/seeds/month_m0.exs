# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Firmowid.Seeds.MonthM0 do
  @moduledoc """
  Seeds for M-0 (current month) — mostly unmatched, KSeF showcase.

  Unmatched transactions (raw bank feed): TacoOverflow partial, OVH, Regus,
    OpenCode, Biuro Plus, ING bank fee, GitHub.

  Unmatched cost invoice: OVH Cloud (current month).

  KSeF showcase invoices (2 states):
    01/ — plain invoice, no KSeF
    02/ — confirmed draft (locked), not submitted to KSeF

  One matched entry: GhostPet partial month ($3,400).
  THB bank fee: -150 THB (skip_invoicing, :internal).

  S08 deterministic assistant scenario:
    Current-month unmatched sales invoice for Aurora Retail: 1,230.00 PLN.
    (paired with M-1 seeded aggregate transactions in MonthM1)

  Counterparty suggestions scenario:
    Two unlinked invoices for GhostPet and two for Samsung, matching only by
    normalized buyer tax ID, so the management counterparty page can suggest
    linking them.
  """

  alias Firmowid.Ash.Analysis.EntityTag
  alias Firmowid.Ash.Invoicing.SalesInvoice, as: AshSalesInvoice
  alias Firmowid.Seeds.Helpers

  require Ash.Query

  @seed_actor %{id: "00000000-0000-0000-0000-000000000000", role: :admin}

  def seed!(ctx) do
    %{bytecraft: bytecraft, bank_accounts: banks, projects: projects, counterparties: cps} = ctx

    prefix = Helpers.month_prefix(0)

    seed_unmatched_transactions(bytecraft, banks)
    seed_thb_fee(bytecraft, banks)
    seed_matched_ghostpet(bytecraft, banks, projects, cps, prefix)
    seed_unmatched_cost_invoice(bytecraft, prefix)
    seed_ksef_scenarios(bytecraft, prefix)
    seed_s08_current_month_invoice(bytecraft, prefix)
    seed_counterparty_suggestion_invoices(bytecraft, cps)
  end

  # — Unmatched transactions (raw bank feed) —

  defp seed_unmatched_transactions(bytecraft, banks) do
    transactions = [
      %{
        internal_transaction_id: "m0_taco_partial",
        creditor_name: "Bytecraft Collective sp. z o.o.",
        creditor_account: "PL85105000997603123456789013",
        debtor_name: "TacoOverflow Inc.",
        debtor_account: "DE89370400440532013000",
        amount: Helpers.money!("EUR", 3_250.00),
        booking_date: Helpers.date_this_month(3),
        bank_account_id: banks.eur.id,
        organization_id: bytecraft.id,
        skip_invoicing: false,
        remittance_information_unstructured: "Częściowa — TacoOverflow sprint Serii A"
      },
      %{
        internal_transaction_id: "m0_ovh",
        creditor_name: "OVH Cloud Sp. z o.o.",
        creditor_account: "PL50102013300000210201234567",
        debtor_name: "Bytecraft Collective sp. z o.o.",
        debtor_account: "PL61105000997603123456789012",
        amount: Helpers.money!("PLN", -2_400.00),
        booking_date: Helpers.date_this_month(5),
        bank_account_id: banks.pln.id,
        organization_id: bytecraft.id,
        skip_invoicing: false,
        remittance_information_unstructured: "OVH Cloud — serwery dedykowane"
      },
      %{
        internal_transaction_id: "m0_rent",
        creditor_name: "Regus Business Centre Sp. z o.o.",
        creditor_account: "PL15109024020000000134672891",
        debtor_name: "Bytecraft Collective sp. z o.o.",
        debtor_account: "PL61105000997603123456789012",
        amount: Helpers.money!("PLN", -4_500.00),
        booking_date: Helpers.date_this_month(1),
        bank_account_id: banks.pln.id,
        organization_id: bytecraft.id,
        skip_invoicing: false,
        remittance_information_unstructured: "Regus — wynajem biura"
      },
      %{
        internal_transaction_id: "m0_opencode",
        creditor_name: "OpenCode GmbH",
        creditor_account: "DE44500105175407324931",
        debtor_name: "Bytecraft Collective sp. z o.o.",
        debtor_account: "PL85105000997603123456789013",
        amount: Helpers.money!("EUR", -120.00),
        booking_date: Helpers.date_this_month(7),
        bank_account_id: banks.eur.id,
        organization_id: bytecraft.id,
        skip_invoicing: false,
        remittance_information_unstructured: "OpenCode Zen — asystent AI do programowania"
      },
      %{
        internal_transaction_id: "m0_biuro",
        creditor_name: "Biuro Plus Sp. z o.o.",
        creditor_account: "PL88109024020000000139876543",
        debtor_name: "Bytecraft Collective sp. z o.o.",
        debtor_account: "PL61105000997603123456789012",
        amount: Helpers.money!("PLN", -550.00),
        booking_date: Helpers.date_this_month(8),
        bank_account_id: banks.pln.id,
        organization_id: bytecraft.id,
        skip_invoicing: false,
        remittance_information_unstructured: "Biuro Plus — materiały biurowe, krzesło ergonomiczne"
      },
      %{
        internal_transaction_id: "m0_bankfee_pln",
        creditor_name: "ING Bank Śląski S.A.",
        creditor_account: "INTERNAL",
        debtor_name: "Bytecraft Collective sp. z o.o.",
        debtor_account: "PL61105000997603123456789012",
        amount: Helpers.money!("PLN", -25.00),
        booking_date: Helpers.date_this_month(1),
        bank_account_id: banks.pln.id,
        organization_id: bytecraft.id,
        skip_invoicing: true,
        remittance_information_unstructured: "Opłata za prowadzenie rachunku"
      },
      %{
        internal_transaction_id: "m0_github",
        creditor_name: "GitHub, Inc.",
        creditor_account: "N/A",
        debtor_name: "Bytecraft Collective sp. z o.o.",
        debtor_account: "PL42105000997603123456789014",
        amount: Helpers.money!("USD", -250.00),
        booking_date: Helpers.date_this_month(3),
        bank_account_id: banks.usd.id,
        organization_id: bytecraft.id,
        skip_invoicing: false,
        remittance_information_unstructured: "GitHub Actions CI/CD + Copilot Business"
      }
    ]

    Enum.each(transactions, fn attrs ->
      Helpers.seed_transaction!(Map.delete(attrs, :organization_id), bytecraft.id)
    end)
  end

  # — THB bank fee —

  defp seed_thb_fee(bytecraft, banks) do
    txn =
      Helpers.seed_transaction!(
        %{
          internal_transaction_id: "m0_thb_bankfee",
          creditor_name: "Bank Millennium S.A.",
          creditor_account: "INTERNAL",
          debtor_name: "Bytecraft Collective sp. z o.o.",
          debtor_account: "PL73116022020000000512345678",
          amount: Helpers.money!("THB", -150.00),
          booking_date: Helpers.date_this_month(1),
          bank_account_id: banks.thb.id,
          skip_invoicing: true,
          remittance_information_unstructured: "Opłata za prowadzenie rachunku walutowego THB"
        },
        bytecraft.id
      )

    EntityTag.set_entity_category!(
      %{entity_type: :transaction, resource_id: txn.id, kind: :internal},
      scope: seed_scope(bytecraft)
    )
  end

  # — Matched: GhostPet partial month —

  defp seed_matched_ghostpet(bytecraft, banks, projects, cps, prefix) do
    txn =
      Helpers.seed_transaction!(
        %{
          internal_transaction_id: "m0_sale_ghostpet",
          creditor_name: "Bytecraft Collective sp. z o.o.",
          creditor_account: "PL42105000997603123456789014",
          debtor_name: "GhostPet Inc.",
          debtor_account: "N/A",
          amount: Helpers.money!("USD", 3_400.00),
          booking_date: Helpers.date_this_month(10),
          bank_account_id: banks.usd.id,
          skip_invoicing: false,
          remittance_information_unstructured: "Faktura BC/05/#{prefix} — GhostPet niepełny miesiąc"
        },
        bytecraft.id
      )

    invoice =
      Helpers.get_or_create_sales_invoice("BC/05/#{prefix}", bytecraft.id, %{
        "invoice_type" => "foreign",
        "issue_date" => Helpers.date_this_month(9),
        "sale_date" => Helpers.date_this_month(8),
        "due_date" => Helpers.date_this_month(22),
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
            "name" => "GhostPet silnik rozmów — rozwój w niepełnym miesiącu",
            "quantity" => 20,
            "unit" => "godz.",
            "unit_price" => 170.00,
            "vat_rate" => "np I"
          }
        ]
      })

    Helpers.connect_sales_invoice_transaction!(invoice.id, txn.id, bytecraft.id)

    EntityTag.set_entity_project_tags!(
      %{
        entity_type: :sales_invoice,
        resource_id: invoice.id,
        tag_definition_ids: [projects.ghostpet.tag_definition_id]
      },
      scope: seed_scope(bytecraft)
    )
  end

  # — Unmatched cost invoice —

  defp seed_unmatched_cost_invoice(bytecraft, prefix) do
    Helpers.get_or_create_cost_invoice("OVH/#{prefix}", bytecraft.id, %{
      seller: "OVH Cloud Sp. z o.o.",
      seller_display_name: "OVH Cloud",
      seller_address: "ul. Swobodna 1, 50-088 Wrocław",
      sale_date: Helpers.date_this_month(1),
      issue_date: Helpers.date_this_month(5),
      due_date: Helpers.date_this_month(19),
      total_amount: -2_400.00,
      currency: "PLN",
      description: "Serwery dedykowane — środowisko produkcyjne + staging",
      skip_invoicing: false
    })
  end

  # — KSeF test scenarios —
  # All 4 invoices are domestic (PLN, VAT 23%) to a fictional but in-domain
  # Polish startup that Bytecraft helped with a short consulting gig.

  @ksef_buyer %{
    "buyer_display_name" => "NexaTech",
    "buyer_full_name" => "NexaTech Sp. z o.o.",
    "buyer_address" => "ul. Mokotowska 15/3, 00-640 Warszawa",
    "buyer_country" => "PL",
    "buyer_id" => "5213843765",
    "buyer_type" => "company",
    "payment_method" => "transfer",
    "is_reverse_charge" => false,
    "is_cash_account" => false
  }

  defp seed_ksef_scenarios(bytecraft, prefix) do
    seed_ksef_plain(bytecraft, prefix)
    seed_ksef_confirmed_not_sent(bytecraft, prefix)
  end

  # 01/ — plain domestic invoice, no KSeF interaction
  defp seed_ksef_plain(bytecraft, prefix) do
    Helpers.get_or_create_sales_invoice(
      "BC/01/#{prefix}",
      bytecraft.id,
      Map.merge(@ksef_buyer, %{
        "invoice_type" => "poland",
        "issue_date" => Helpers.date_this_month(15),
        "sale_date" => Helpers.date_this_month(15),
        "due_date" => Helpers.date_this_month(28),
        "currency" => "PLN",
        "sales_invoice_items" => [
          %{
            "name" => "Audyt architektury — migracja do mikroserwisów",
            "quantity" => 40,
            "unit" => "godz.",
            "unit_price" => 250.00,
            "vat_rate" => "23"
          },
          %{
            "name" => "Konsultacje DevOps — konfiguracja CI/CD",
            "quantity" => 8,
            "unit" => "godz.",
            "unit_price" => 300.00,
            "vat_rate" => "23"
          }
        ]
      })
    )
  end

  # 02/ — confirmed draft (locked), not submitted to KSeF
  defp seed_ksef_confirmed_not_sent(bytecraft, prefix) do
    inv_number = "BC/02/#{prefix}"

    existing = find_sales_invoice(inv_number, bytecraft.id)

    if is_nil(existing) do
      invoice =
        Helpers.get_or_create_sales_invoice(
          inv_number,
          bytecraft.id,
          Map.merge(@ksef_buyer, %{
            "invoice_type" => "poland",
            "issue_date" => Helpers.date_this_month(10),
            "sale_date" => Helpers.date_this_month(10),
            "due_date" => Helpers.date_this_month(24),
            "currency" => "PLN",
            "sales_invoice_items" => [
              %{
                "name" => "Prototyp MVP — panel analityczny NexaTech",
                "quantity" => 10,
                "unit" => "godz.",
                "unit_price" => 200.00,
                "vat_rate" => "23"
              }
            ]
          })
        )

      Ash.Seed.update!(invoice, %{
        locked_at: DateTime.truncate(DateTime.utc_now(), :second)
      })
    end
  end

  # — S08 deterministic assistant scenario (current month invoice) —

  defp seed_s08_current_month_invoice(bytecraft, prefix) do
    Helpers.get_or_create_sales_invoice("AUR/#{prefix}", bytecraft.id, %{
      "invoice_type" => "poland",
      "issue_date" => Helpers.date_this_month(14),
      "sale_date" => Helpers.date_this_month(14),
      "due_date" => Helpers.date_this_month(28),
      "currency" => "PLN",
      "buyer_display_name" => "Aurora Retail Sp. z o.o.",
      "buyer_full_name" => "Aurora Retail Sp. z o.o.",
      "buyer_address" => "ul. Handlowa 12, 00-950 Warszawa",
      "buyer_country" => "PL",
      "buyer_id" => "5252445767",
      "buyer_type" => "company",
      "payment_method" => "transfer",
      "is_reverse_charge" => false,
      "is_cash_account" => false,
      "sales_invoice_items" => [
        %{
          "name" => "Pakiet wdrożeniowy Aurora Retail",
          "quantity" => 1,
          "unit" => "szt.",
          "unit_price" => 1000.00,
          "vat_rate" => "23"
        }
      ]
    })
  end

  # — Counterparty suggestions on management page —

  defp seed_counterparty_suggestion_invoices(bytecraft, cps) do
    seed_ghostpet_suggestion_invoices(bytecraft, cps)
    seed_samsung_suggestion_invoices(bytecraft, cps)
  end

  defp seed_ghostpet_suggestion_invoices(bytecraft, cps) do
    base_attrs = %{
      "invoice_type" => "foreign",
      "buyer_display_name" => "GhostPet Inc.",
      "buyer_full_name" => "GhostPet Inc.",
      "buyer_address" => "440 N Barranca Ave #7658, Covina, CA 91723",
      "buyer_country" => "US",
      "buyer_type" => "company",
      "payment_method" => "transfer",
      "is_reverse_charge" => false,
      "is_cash_account" => false,
      "sales_invoice_items" => [
        %{
          "name" => "GhostPet — test dopasowania kontrahenta po znormalizowanym identyfikatorze",
          "quantity" => 12,
          "unit" => "godz.",
          "unit_price" => 170.00,
          "vat_rate" => "np I"
        }
      ]
    }

    Helpers.get_or_create_sales_invoice(
      "UI/GHOST/01/2026",
      bytecraft.id,
      Map.merge(base_attrs, %{
        "issue_date" => Helpers.date_this_month(16),
        "sale_date" => Helpers.date_this_month(16),
        "due_date" => Helpers.date_this_month(30),
        "currency" => "USD",
        "buyer_id" => "US EIN 47 8830291"
      })
    )

    Helpers.get_or_create_sales_invoice(
      "UI/GHOST/02/2026",
      bytecraft.id,
      Map.merge(base_attrs, %{
        "issue_date" => Helpers.date_this_month(17),
        "sale_date" => Helpers.date_this_month(17),
        "due_date" => Helpers.date_this_month(min(Date.days_in_month(Helpers.today()), 31)),
        "currency" => "USD",
        "buyer_id" => "us-ein-47-8830291"
      })
    )

    cps
  end

  defp seed_samsung_suggestion_invoices(bytecraft, cps) do
    base_attrs = %{
      "invoice_type" => "foreign",
      "buyer_display_name" => "Samsung",
      "buyer_full_name" => "Samsung",
      "buyer_address" => "Huwaeng 12321/321, Seoul",
      "buyer_country" => "KR",
      "buyer_type" => "company",
      "payment_method" => "transfer",
      "is_reverse_charge" => false,
      "is_cash_account" => false,
      "sales_invoice_items" => [
        %{
          "name" => "Samsung — wdrożenie panelu partnera",
          "quantity" => 20,
          "unit" => "godz.",
          "unit_price" => 170.00,
          "vat_rate" => "np I"
        }
      ]
    }

    Helpers.get_or_create_sales_invoice(
      "UI/SAMSUNG/01/2026",
      bytecraft.id,
      Map.merge(base_attrs, %{
        "issue_date" => Helpers.date_this_month(19),
        "sale_date" => Helpers.date_this_month(19),
        "due_date" => Helpers.date_this_month(min(Date.days_in_month(Helpers.today()), 31)),
        "currency" => "USD",
        "buyer_id" => "123-123-12"
      })
    )

    Helpers.get_or_create_sales_invoice(
      "UI/SAMSUNG/02/2026",
      bytecraft.id,
      Map.merge(base_attrs, %{
        "issue_date" => Helpers.date_this_month(20),
        "sale_date" => Helpers.date_this_month(20),
        "due_date" => Helpers.date_this_month(min(Date.days_in_month(Helpers.today()), 31)),
        "currency" => "USD",
        "buyer_id" => "123 123 12"
      })
    )

    cps
  end

  # Builds a scope for Ash calls in seeds. Uses bytecraft.id as tenant and a
  # synthetic admin actor to bypass policies.
  defp seed_scope(bytecraft) do
    %Firmowid.Ash.Scope{
      actor: %{id: "00000000-0000-0000-0000-000000000000", role: :admin},
      tenant: bytecraft.id
    }
  end

  defp find_sales_invoice(inv_number, org_id) do
    query =
      AshSalesInvoice
      |> Ash.Query.filter(invoice_number == ^inv_number and organization_id == ^org_id)
      |> Ash.Query.limit(1)

    case Ash.read(query, tenant: org_id, actor: @seed_actor) do
      {:ok, [invoice | _]} -> invoice
      _ -> nil
    end
  end
end
