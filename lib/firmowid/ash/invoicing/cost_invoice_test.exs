defmodule Firmowid.Ash.Invoicing.CostInvoiceTest do
  @moduledoc false
  use Firmowid.DataCase, async: false

  import Firmowid.AccountsFixtures
  import Firmowid.Test.Support.OpenAIEnrichmentTestHelpers

  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Scope

  require Ash.Query

  setup do
    original_openai_enrichment = Application.get_env(:firmowid, :openai_enrichment)

    Application.put_env(
      :firmowid,
      :openai_enrichment,
      request_options: [plug: {Req.Test, :openai_enrichment}]
    )

    stub_openai_enrichment_request()

    on_exit(fn -> restore_env(:openai_enrichment, original_openai_enrichment) end)
  end

  describe "delete_cost_invoice/1" do
    test "returns error for KSeF-imported invoice and does not delete it" do
      user = admin_fixture()
      invoice = insert_ksef_cost_invoice!(user.organization_id)

      scope = %Scope{actor: user, tenant: user.organization_id}

      assert_raise RuntimeError,
                   ~r/Cost invoice #{invoice.id} is imported from KSeF and cannot be deleted/,
                   fn ->
                     Invoicing.delete_cost_invoice(invoice.id, scope)
                   end

      assert {:ok, _} = Invoicing.get_cost_invoice(invoice.id, scope: scope)
    end
  end

  describe "cost invoice lists" do
    test "hides only corrections whose original invoice exists in list_for_month" do
      user = admin_fixture()
      scope = %Scope{actor: user, tenant: user.organization_id}

      visible_invoice =
        insert_cost_invoice!(user.organization_id, %{invoice_identifier: "VISIBLE-REGULAR"})

      original_invoice =
        insert_cost_invoice!(user.organization_id, %{
          invoice_identifier: "ORIGINAL-INVOICE",
          ksef_number: "KSEF-ORIGINAL-123"
        })

      visible_correction =
        insert_cost_invoice!(user.organization_id, %{
          invoice_identifier: "VISIBLE-CORRECTION",
          invoice_type: :kor,
          original_invoice_ksef_number: nil,
          amount: Money.new!("PLN", "10.00")
        })

      _hidden_correction =
        insert_cost_invoice!(user.organization_id, %{
          invoice_identifier: "HIDDEN-CORRECTION",
          invoice_type: :kor,
          original_invoice_ksef_number: "KSEF-ORIGINAL-123",
          amount: Money.new!("PLN", "10.00")
        })

      orphaned_correction =
        insert_cost_invoice!(user.organization_id, %{
          invoice_identifier: "ORPHANED-CORRECTION",
          invoice_type: :kor,
          original_invoice_ksef_number: "KSEF-MISSING-ORIGINAL-123",
          amount: Money.new!("PLN", "10.00")
        })

      invoices =
        Invoicing.list_cost_invoices!(
          %{
            date_from: ~D[2026-02-01],
            date_to: ~D[2026-02-28],
            date_field: :issue_date,
            corrections: :exclude
          },
          scope: scope
        )

      invoice_ids = Enum.map(invoices, & &1.id)

      assert visible_invoice.id in invoice_ids
      assert original_invoice.id in invoice_ids
      assert visible_correction.id in invoice_ids
      assert orphaned_correction.id in invoice_ids
      refute Enum.any?(invoices, &(&1.invoice_identifier == "HIDDEN-CORRECTION"))
    end

    test "hides only corrections whose original invoice exists from list_unmatched" do
      user = admin_fixture()
      scope = %Scope{actor: user, tenant: user.organization_id}

      visible_invoice =
        insert_cost_invoice!(user.organization_id, %{invoice_identifier: "VISIBLE-UNMATCHED"})

      original_invoice =
        insert_cost_invoice!(user.organization_id, %{
          invoice_identifier: "ORIGINAL-UNMATCHED-INVOICE",
          ksef_number: "KSEF-ORIGINAL-456"
        })

      visible_correction =
        insert_cost_invoice!(user.organization_id, %{
          invoice_identifier: "VISIBLE-UNMATCHED-CORRECTION",
          invoice_type: :kor,
          original_invoice_ksef_number: nil,
          amount: Money.new!("PLN", "12.34")
        })

      _hidden_correction =
        insert_cost_invoice!(user.organization_id, %{
          invoice_identifier: "HIDDEN-UNMATCHED-CORRECTION",
          invoice_type: :kor,
          original_invoice_ksef_number: "KSEF-ORIGINAL-456",
          amount: Money.new!("PLN", "12.34")
        })

      orphaned_correction =
        insert_cost_invoice!(user.organization_id, %{
          invoice_identifier: "ORPHANED-UNMATCHED-CORRECTION",
          invoice_type: :kor,
          original_invoice_ksef_number: "KSEF-MISSING-ORIGINAL-456",
          amount: Money.new!("PLN", "12.34")
        })

      invoices =
        Invoicing.list_cost_invoices!(
          %{
            date_from: ~D[2026-02-01],
            date_to: ~D[2026-02-28],
            date_field: :due_date,
            reconciliation: :pending,
            corrections: :exclude
          },
          scope: scope
        )

      invoice_ids = Enum.map(invoices, & &1.id)

      assert visible_invoice.id in invoice_ids
      assert original_invoice.id in invoice_ids
      assert visible_correction.id in invoice_ids
      assert orphaned_correction.id in invoice_ids
      refute Enum.any?(invoices, &(&1.invoice_identifier == "HIDDEN-UNMATCHED-CORRECTION"))
    end
  end

  describe "create" do
    test "persists a Money amount" do
      user = admin_fixture()
      scope = %Scope{actor: user, tenant: user.organization_id}

      assert {:ok, invoice} =
               CostInvoice.create(
                 %{
                   seller: "Supplier Sp. z o.o.",
                   sale_date: ~D[2026-02-01],
                   issue_date: ~D[2026-02-01],
                   items_list: [],
                   amount: Money.new!("PLN", "-123.45"),
                   invoice_identifier: "FV/2026/02/AMOUNT"
                 },
                 scope: scope
               )

      assert Money.to_decimal(invoice.amount) == Decimal.new("-123.45")
      assert Money.to_currency_code(invoice.amount) == :PLN
    end

    test "keeps the original amount when the latest correction changes currency" do
      user = admin_fixture()
      scope = %Scope{actor: user, tenant: user.organization_id}

      original =
        insert_cost_invoice!(user.organization_id, %{
          ksef_number: "KSEF-ORIGINAL-CURRENCY"
        })

      assert {:ok, _correction} =
               CostInvoice.create(
                 %{
                   seller: "Supplier Sp. z o.o.",
                   sale_date: ~D[2026-02-01],
                   issue_date: ~D[2026-02-01],
                   items_list: [],
                   amount: Money.new!("EUR", "10.00"),
                   invoice_identifier: "FV/2026/02/WRONG-CURRENCY",
                   invoice_type: :kor,
                   original_invoice_ksef_number: original.ksef_number
                 },
                 scope: scope
               )

      invoice = Ash.load!(original, [:effective_amount], scope: scope)

      assert Money.to_decimal(invoice.effective_amount) == Decimal.new("-123.45")
      assert Money.to_currency_code(invoice.effective_amount) == :PLN
    end

    test "allows an orphan correction" do
      user = admin_fixture()
      scope = %Scope{actor: user, tenant: user.organization_id}

      assert {:ok, invoice} =
               CostInvoice.create(
                 %{
                   seller: "Supplier Sp. z o.o.",
                   sale_date: ~D[2026-02-01],
                   issue_date: ~D[2026-02-01],
                   items_list: [],
                   amount: Money.new!("EUR", "10.00"),
                   invoice_identifier: "FV/2026/02/ORPHAN",
                   invoice_type: :kor,
                   original_invoice_ksef_number: "KSEF-MISSING-ORIGINAL"
                 },
                 scope: scope
               )

      assert Money.to_currency_code(invoice.amount) == :EUR
    end

    test "allows an original after an orphan correction with a different currency" do
      user = admin_fixture()
      scope = %Scope{actor: user, tenant: user.organization_id}

      assert {:ok, _orphan} =
               CostInvoice.create(
                 %{
                   seller: "Supplier Sp. z o.o.",
                   sale_date: ~D[2026-02-01],
                   issue_date: ~D[2026-02-01],
                   items_list: [],
                   amount: Money.new!("EUR", "10.00"),
                   invoice_identifier: "FV/2026/02/ORPHAN-CORRECTION",
                   invoice_type: :kor,
                   original_invoice_ksef_number: "KSEF-LATE-ORIGINAL"
                 },
                 scope: scope
               )

      assert {:ok, _original} =
               CostInvoice.create(
                 %{
                   seller: "Supplier Sp. z o.o.",
                   sale_date: ~D[2026-02-01],
                   issue_date: ~D[2026-02-01],
                   items_list: [],
                   amount: Money.new!("PLN", "-100.00"),
                   invoice_identifier: "FV/2026/02/LATE-ORIGINAL",
                   ksef_number: "KSEF-LATE-ORIGINAL"
                 },
                 scope: scope
               )
    end

    test "rejects a positive non-correction amount" do
      user = admin_fixture()
      scope = %Scope{actor: user, tenant: user.organization_id}

      assert {:error, error} =
               CostInvoice.create(
                 %{
                   seller: "Supplier Sp. z o.o.",
                   sale_date: ~D[2026-02-01],
                   issue_date: ~D[2026-02-01],
                   items_list: [],
                   amount: Money.new!("PLN", "100.00"),
                   invoice_identifier: "FV/2026/02/POSITIVE"
                 },
                 scope: scope
               )

      assert Exception.message(error) =~ "must be <= 0 for non-correction invoices"
    end
  end

  describe "effective amount" do
    test "sums same-currency correction deltas as Money" do
      user = admin_fixture()
      scope = %Scope{actor: user, tenant: user.organization_id}

      original =
        insert_cost_invoice!(user.organization_id, %{
          ksef_number: "KSEF-EFFECTIVE-AMOUNT",
          amount: Money.new!("PLN", "-100.00")
        })

      insert_cost_invoice!(user.organization_id, %{
        invoice_type: :kor,
        original_invoice_ksef_number: original.ksef_number,
        amount: Money.new!("PLN", "20.00")
      })

      insert_cost_invoice!(user.organization_id, %{
        invoice_type: :kor,
        original_invoice_ksef_number: original.ksef_number,
        amount: Money.new!("PLN", "-5.00")
      })

      invoice = Ash.load!(original, [:corrections_amount, :effective_amount], scope: scope)

      assert invoice.corrections_amount == Decimal.new("15.00")
      assert Money.to_decimal(invoice.effective_amount) == Decimal.new("-85.00")
      assert Money.to_currency_code(invoice.effective_amount) == :PLN
    end

    test "excludes a historical correction in another currency" do
      user = admin_fixture()
      scope = %Scope{actor: user, tenant: user.organization_id}

      original =
        insert_cost_invoice!(user.organization_id, %{
          ksef_number: "KSEF-EFFECTIVE-MULTI-CURRENCY",
          amount: Money.new!("PLN", "-100.00")
        })

      insert_cost_invoice!(user.organization_id, %{
        invoice_type: :kor,
        original_invoice_ksef_number: original.ksef_number,
        amount: Money.new!("EUR", "10.00"),
        ksef_permanent_storage_date: ~N[2026-02-01 12:00:00]
      })

      insert_cost_invoice!(user.organization_id, %{
        invoice_type: :kor,
        original_invoice_ksef_number: original.ksef_number,
        amount: Money.new!("PLN", "5.00"),
        ksef_permanent_storage_date: ~N[2026-02-02 12:00:00]
      })

      invoice = Ash.load!(original, [:corrections_amount, :effective_amount], scope: scope)

      assert invoice.corrections_amount == Decimal.new("5.00")
      assert Money.to_decimal(invoice.effective_amount) == Decimal.new("-95.00")
      assert Money.to_currency_code(invoice.effective_amount) == :PLN
    end

    test "keeps an orphan correction out of an invoice effective amount" do
      user = admin_fixture()
      scope = %Scope{actor: user, tenant: user.organization_id}

      original =
        insert_cost_invoice!(user.organization_id, %{amount: Money.new!("PLN", "-100.00")})

      insert_cost_invoice!(user.organization_id, %{
        invoice_type: :kor,
        original_invoice_ksef_number: "KSEF-NOT-PRESENT",
        amount: Money.new!("PLN", "20.00")
      })

      invoice = Ash.load!(original, [:effective_amount], scope: scope)

      assert Money.to_decimal(invoice.effective_amount) == Decimal.new("-100.00")
    end

    test "filters and sorts effective amounts in PostgreSQL" do
      user = admin_fixture()
      scope = %Scope{actor: user, tenant: user.organization_id}

      first_invoice =
        insert_cost_invoice!(user.organization_id, %{
          ksef_number: "KSEF-EFFECTIVE-QUERY-FIRST",
          amount: Money.new!("PLN", "-100.00")
        })

      second_invoice =
        insert_cost_invoice!(user.organization_id, %{
          ksef_number: "KSEF-EFFECTIVE-QUERY-SECOND",
          amount: Money.new!("PLN", "-100.00")
        })

      insert_cost_invoice!(user.organization_id, %{
        invoice_type: :kor,
        original_invoice_ksef_number: first_invoice.ksef_number,
        amount: Money.new!("PLN", "15.00")
      })

      insert_cost_invoice!(user.organization_id, %{
        invoice_type: :kor,
        original_invoice_ksef_number: second_invoice.ksef_number,
        amount: Money.new!("PLN", "25.00")
      })

      invoices =
        CostInvoice
        |> Ash.Query.filter(
          is_nil(original_invoice_ksef_number) and
            effective_amount > ^Money.new!("PLN", Decimal.new("-90.00"))
        )
        |> Ash.Query.sort(effective_amount: :desc)
        |> Ash.Query.load(:effective_amount)
        |> Ash.read!(scope: scope)

      assert Enum.map(invoices, & &1.id) == [second_invoice.id, first_invoice.id]

      assert Enum.map(invoices, &Money.to_decimal(&1.effective_amount)) == [
               Decimal.new("-75.00"),
               Decimal.new("-85.00")
             ]
    end
  end

  defp insert_ksef_cost_invoice!(organization_id) do
    Ash.Seed.seed!(CostInvoice, %{
      seller: "KSeF Supplier Sp. z o.o.",
      seller_display_name: "KSeF Supplier",
      seller_address: "ul. Przykładowa 1, 00-001 Warszawa",
      sale_date: ~D[2026-02-01],
      issue_date: ~D[2026-02-01],
      due_date: ~D[2026-02-14],
      amount: Money.new!("PLN", Decimal.new("-123.45")),
      description: "Import z KSeF",
      invoice_identifier: "FV/2026/02/001",
      skip_invoicing: false,
      organization_id: organization_id,
      ksef_number: "KSEF-2026-TEST-#{System.unique_integer([:positive])}",
      ksef_permanent_storage_date: ~N[2026-02-01 12:00:00],
      ksef_downloaded_at: DateTime.utc_now()
    })
  end

  defp restore_env(key, nil), do: Application.delete_env(:firmowid, key)
  defp restore_env(key, value), do: Application.put_env(:firmowid, key, value)

  defp insert_cost_invoice!(organization_id, attrs) do
    base_attrs = %{
      seller: "Supplier Sp. z o.o.",
      seller_display_name: "Supplier",
      seller_address: "ul. Testowa 1, 00-001 Warszawa",
      sale_date: ~D[2026-02-01],
      issue_date: ~D[2026-02-01],
      due_date: ~D[2026-02-14],
      amount: Money.new!("PLN", "-123.45"),
      description: "Test invoice",
      invoice_identifier: "FV/2026/02/#{System.unique_integer([:positive])}",
      skip_invoicing: false,
      organization_id: organization_id
    }

    Ash.Seed.seed!(CostInvoice, Map.merge(base_attrs, attrs))
  end
end
