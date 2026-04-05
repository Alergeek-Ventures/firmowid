# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Firmowid.Seeds.MonthM0 do
  @moduledoc """
  Seeds for M-0 (current month) — mostly unmatched, KSeF showcase.

  Unmatched transactions (raw bank feed): TacoOverflow partial, OVH, Regus,
    OpenCode, Biuro Plus, ING bank fee, GitHub.

  Unmatched cost invoice: OVH Cloud (current month).

  KSeF showcase invoices (4 states):
    01/ — plain invoice, no KSeF
    02/ — KSeF success (has ksef_number, locked)
    03/ — KSeF sending (locked, Oban job executing)
    04/ — KSeF failed (locked, Oban job discarded with errors)

  One matched entry: GhostPet partial month ($3,400).
  THB bank fee: -150 THB (skip_invoicing, :internal).
  """

  import Ecto.Query

  alias Firmowid.Ash.Analysis.EntityTag
  alias Firmowid.Ash.Finances.Transaction, as: AshTransaction
  alias Firmowid.Ash.Invoicing.SalesInvoice, as: AshSalesInvoice
  alias Firmowid.Repo
  alias Firmowid.Seeds.Helpers

  def seed!(ctx) do
    %{bytecraft: bytecraft, bank_accounts: banks, projects: projects, counterparties: cps} = ctx

    prefix = Helpers.month_prefix(0)

    seed_unmatched_transactions(bytecraft, banks)
    seed_thb_fee(bytecraft, banks)
    seed_matched_ghostpet(bytecraft, banks, projects, cps, prefix)
    seed_unmatched_cost_invoice(bytecraft, prefix)
    seed_ksef_scenarios(bytecraft, prefix)
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
        transaction_amount: 3_250.00,
        transaction_currency: "EUR",
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
        transaction_amount: -2_400.00,
        transaction_currency: "PLN",
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
        transaction_amount: -4_500.00,
        transaction_currency: "PLN",
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
        transaction_amount: -120.00,
        transaction_currency: "EUR",
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
        transaction_amount: -550.00,
        transaction_currency: "PLN",
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
        transaction_amount: -25.00,
        transaction_currency: "PLN",
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
        transaction_amount: -250.00,
        transaction_currency: "USD",
        booking_date: Helpers.date_this_month(3),
        bank_account_id: banks.usd.id,
        organization_id: bytecraft.id,
        skip_invoicing: false,
        remittance_information_unstructured: "GitHub Actions CI/CD + Copilot Business"
      }
    ]

    transactions
    |> Enum.map(&Map.delete(&1, :organization_id))
    |> Ash.bulk_create!(AshTransaction, :upsert_from_sync,
      tenant: bytecraft.id,
      authorize?: false,
      actor: %{}
    )
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
          transaction_amount: -150.00,
          transaction_currency: "THB",
          booking_date: Helpers.date_this_month(1),
          bank_account_id: banks.thb.id,
          skip_invoicing: true,
          remittance_information_unstructured: "Opłata za prowadzenie rachunku walutowego THB"
        },
        bytecraft.id
      )

    EntityTag.set_entity_category!(
      %{entity_type: :transaction, resource_id: txn.id, kind: :internal},
      scope: seed_scope()
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
          transaction_amount: 3_400.00,
          transaction_currency: "USD",
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

    Firmowid.Ash.Invoicing.connect_sales_invoice_transactions!(
      invoice,
      [txn.id],
      tenant: bytecraft.id,
      authorize?: false,
      actor: %{}
    )

    EntityTag.set_entity_project_tags!(
      %{
        entity_type: :sales_invoice,
        resource_id: invoice.id,
        tag_definition_ids: [projects.ghostpet.tag_definition_id]
      },
      scope: seed_scope()
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
    "buyer_id" => "5213843762",
    "buyer_type" => "company",
    "payment_method" => "transfer",
    "is_reverse_charge" => false,
    "is_cash_account" => false
  }

  defp seed_ksef_scenarios(bytecraft, prefix) do
    seed_ksef_plain(bytecraft, prefix)
    seed_ksef_success(bytecraft, prefix)
    seed_ksef_sending(bytecraft, prefix)
    seed_ksef_failed(bytecraft, prefix)
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

  # 02/ — KSeF success (has ksef_number, locked)
  defp seed_ksef_success(bytecraft, prefix) do
    inv_number = "BC/02/#{prefix}"

    existing =
      Repo.one(
        from(si in AshSalesInvoice,
          where: si.invoice_number == ^inv_number and si.organization_id == ^bytecraft.id,
          limit: 1
        )
      )

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
        ksef_number: "5213843762-20250110-ABC123DEF456-00",
        ksef_session_reference_number: "20250110-SE-ABC123DEF456-00",
        ksef_invoice_checksum: "dGVzdC1jaGVja3N1bS1mb3Ita3NlZi1zZWVk",
        locked_at: DateTime.truncate(DateTime.utc_now(), :second)
      })
    end
  end

  # 03/ — KSeF sending (locked, Oban job executing)
  defp seed_ksef_sending(bytecraft, prefix) do
    inv_number = "BC/03/#{prefix}"

    existing =
      Repo.one(
        from(si in AshSalesInvoice,
          where: si.invoice_number == ^inv_number and si.organization_id == ^bytecraft.id,
          limit: 1
        )
      )

    if is_nil(existing) do
      invoice =
        Helpers.get_or_create_sales_invoice(
          inv_number,
          bytecraft.id,
          Map.merge(@ksef_buyer, %{
            "invoice_type" => "poland",
            "issue_date" => Helpers.date_this_month(5),
            "sale_date" => Helpers.date_this_month(5),
            "due_date" => Helpers.date_this_month(19),
            "currency" => "PLN",
            "sales_invoice_items" => [
              %{
                "name" => "Szkolenie zespołu — Elixir i Phoenix LiveView",
                "quantity" => 5,
                "unit" => "godz.",
                "unit_price" => 150.00,
                "vat_rate" => "23"
              }
            ]
          })
        )

      Ash.Seed.update!(invoice, %{
        ksef_session_reference_number: "20250115-SE-SENDING123-00",
        locked_at: DateTime.truncate(DateTime.utc_now(), :second)
      })

      Repo.query!(
        """
        INSERT INTO oban.oban_jobs (state, queue, worker, args, attempt, max_attempts, inserted_at, scheduled_at, attempted_at, priority, tags, meta)
        VALUES ('executing', 'ksef_submissions', 'Firmowid.Ash.Ksef.Workers.SubmissionWorker',
                $1::jsonb, 1, 3, NOW(), NOW(), NOW(), 0, ARRAY[]::text[], $2::jsonb)
        ON CONFLICT DO NOTHING
        """,
        [
          %{
            "action" => "verify",
            "organization_id" => bytecraft.id,
            "sales_invoice_id" => invoice.id,
            "session_reference" => "20250115-SE-SENDING123-00",
            "invoice_reference" => "INV-REF-SENDING-001"
          },
          %{"organization_id" => bytecraft.id}
        ]
      )
    end
  end

  # 04/ — KSeF failed (locked, Oban job discarded with errors)
  defp seed_ksef_failed(bytecraft, prefix) do
    inv_number = "BC/04/#{prefix}"

    existing =
      Repo.one(
        from(si in AshSalesInvoice,
          where: si.invoice_number == ^inv_number and si.organization_id == ^bytecraft.id,
          limit: 1
        )
      )

    if is_nil(existing) do
      invoice =
        Helpers.get_or_create_sales_invoice(
          inv_number,
          bytecraft.id,
          Map.merge(@ksef_buyer, %{
            "invoice_type" => "poland",
            "issue_date" => Helpers.date_this_month(3),
            "sale_date" => Helpers.date_this_month(3),
            "due_date" => Helpers.date_this_month(17),
            "currency" => "PLN",
            "sales_invoice_items" => [
              %{
                "name" => "Wsparcie przy wdrożeniu — monitoring i alerty",
                "quantity" => 3,
                "unit" => "godz.",
                "unit_price" => 100.00,
                "vat_rate" => "23"
              }
            ]
          })
        )

      Ash.Seed.update!(invoice, %{
        ksef_session_reference_number: "20250120-SE-FAILED456-00",
        locked_at: DateTime.truncate(DateTime.utc_now(), :second)
      })

      Repo.query!(
        """
        INSERT INTO oban.oban_jobs (state, queue, worker, args, attempt, max_attempts, inserted_at, scheduled_at, discarded_at, priority, tags, meta, errors)
        VALUES ('discarded', 'ksef_submissions', 'Firmowid.Ash.Ksef.Workers.SubmissionWorker',
                $1::jsonb, 3, 3, NOW() - INTERVAL '1 hour', NOW() - INTERVAL '1 hour', NOW(), 0, ARRAY[]::text[], $2::jsonb,
                ARRAY[
                  '{"at": "2025-01-20T14:05:00Z", "attempt": 1, "error": "KSeF API error: connection timeout"}',
                  '{"at": "2025-01-20T14:10:00Z", "attempt": 2, "error": "KSeF API error: connection timeout"}',
                  '{"at": "2025-01-20T14:15:00Z", "attempt": 3, "error": "KSeF API error: connection timeout"}'
                ]::jsonb[])
        ON CONFLICT DO NOTHING
        """,
        [
          %{
            "action" => "verify",
            "organization_id" => bytecraft.id,
            "sales_invoice_id" => invoice.id,
            "session_reference" => "20250120-SE-FAILED456-00",
            "invoice_reference" => "INV-REF-FAILED-001"
          },
          %{"organization_id" => bytecraft.id}
        ]
      )
    end
  end

  # Builds a scope for Ash calls in seeds. Uses Repo.get_org_id() (already set
  # by Bytecraft.seed!) as tenant and a synthetic admin actor to bypass policies.
  defp seed_scope do
    %Firmowid.Ash.Scope{
      current_user: %{id: "00000000-0000-0000-0000-000000000000", role: :admin},
      current_tenant: Repo.get_org_id()
    }
  end
end
