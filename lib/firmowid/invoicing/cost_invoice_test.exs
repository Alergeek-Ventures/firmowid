defmodule Firmowid.Invoicing.CostInvoiceTest do
  @moduledoc false
  use Firmowid.DataCase, async: false

  import Firmowid.AccountsFixtures
  import Firmowid.FinancesFixtures
  import Firmowid.Test.Support.OpenAIEnrichmentTestHelpers

  alias Ash.Error.Invalid
  alias Firmowid.Finances.Transaction
  alias Firmowid.Invoicing
  alias Firmowid.Invoicing.CostInvoice
  alias Firmowid.Scope

  require Ash.Query

  defmodule FailingSellerDisplayNameGenerator do
    @moduledoc false
    def generate_display_name(_document, _opts), do: nil
  end

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
      invoice = insert_ksef_cost_invoice!(user.member.organization_id)

      scope = %Scope{actor: user, tenant: user.member.organization_id}

      assert_raise RuntimeError,
                   ~r/Cost invoice #{invoice.id} is imported from KSeF and cannot be deleted/,
                   fn ->
                     Invoicing.delete_cost_invoice(invoice.id, scope)
                   end

      assert {:ok, _} = Invoicing.get_cost_invoice(invoice.id, scope: scope)
    end
  end

  describe "cost invoice lists" do
    test "linked corrections cannot be skipped or connected to payments" do
      user = admin_fixture()
      scope = %Scope{actor: user, tenant: user.member.organization_id}
      original = insert_ksef_cost_invoice!(scope.tenant)

      correction =
        insert_cost_invoice!(scope.tenant, %{
          invoice_type: :kor,
          original_invoice_ksef_number: original.ksef_number,
          amount: Money.new!("PLN", "0")
        })

      payment =
        Ash.Seed.seed!(Transaction, %{
          transaction_id: "TX-CORRECTION-#{System.unique_integer([:positive])}",
          internal_transaction_id: "INT-CORRECTION-#{System.unique_integer([:positive])}",
          amount: original.amount,
          booking_date: original.issue_date,
          value_date: original.issue_date,
          bank_account_id: bank_account_fixture!(user).id,
          organization_id: scope.tenant
        })

      assert {:error, %Invalid{}} = Invoicing.toggle_cost_invoice_skip(correction, scope: scope)

      assert {:error,
              %Invalid{
                errors: [%Ash.Error.Changes.InvalidAttribute{field: :transaction_ids}]
              }} =
               Invoicing.connect_cost_invoice_transactions(correction, [payment.id], scope: scope)

      correction = Invoicing.get_cost_invoice!(correction.id, load: [:transactions], scope: scope)
      refute correction.skip_invoicing
      assert correction.transactions == []
    end

    test "hides only corrections whose original invoice exists in list_for_month" do
      user = admin_fixture()
      scope = %Scope{actor: user, tenant: user.member.organization_id}

      visible_invoice =
        insert_cost_invoice!(user.member.organization_id, %{invoice_identifier: "VISIBLE-REGULAR"})

      original_invoice =
        insert_cost_invoice!(user.member.organization_id, %{
          invoice_identifier: "ORIGINAL-INVOICE",
          ksef_number: "KSEF-ORIGINAL-123"
        })

      visible_correction =
        insert_cost_invoice!(user.member.organization_id, %{
          invoice_identifier: "VISIBLE-CORRECTION",
          invoice_type: :kor,
          original_invoice_ksef_number: nil,
          amount: Money.new!("PLN", "10.00")
        })

      _hidden_correction =
        insert_cost_invoice!(user.member.organization_id, %{
          invoice_identifier: "HIDDEN-CORRECTION",
          invoice_type: :kor,
          original_invoice_ksef_number: "KSEF-ORIGINAL-123",
          amount: Money.new!("PLN", "10.00")
        })

      orphaned_correction =
        insert_cost_invoice!(user.member.organization_id, %{
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
            merge_corrections: true
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
      scope = %Scope{actor: user, tenant: user.member.organization_id}

      visible_invoice =
        insert_cost_invoice!(user.member.organization_id, %{
          invoice_identifier: "VISIBLE-UNMATCHED"
        })

      original_invoice =
        insert_cost_invoice!(user.member.organization_id, %{
          invoice_identifier: "ORIGINAL-UNMATCHED-INVOICE",
          ksef_number: "KSEF-ORIGINAL-456"
        })

      visible_correction =
        insert_cost_invoice!(user.member.organization_id, %{
          invoice_identifier: "VISIBLE-UNMATCHED-CORRECTION",
          invoice_type: :kor,
          original_invoice_ksef_number: nil,
          amount: Money.new!("PLN", "12.34")
        })

      _hidden_correction =
        insert_cost_invoice!(user.member.organization_id, %{
          invoice_identifier: "HIDDEN-UNMATCHED-CORRECTION",
          invoice_type: :kor,
          original_invoice_ksef_number: "KSEF-ORIGINAL-456",
          amount: Money.new!("PLN", "12.34")
        })

      orphaned_correction =
        insert_cost_invoice!(user.member.organization_id, %{
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
            merge_corrections: true
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

  describe "update_blob_id" do
    test "attaches a blob only for document processing" do
      admin = admin_fixture()
      organization_id = admin.member.organization_id
      invoice = insert_ksef_cost_invoice!(organization_id)

      blob =
        Ash.Seed.seed!(Firmowid.Blobs.Blob, %{
          blob_path: "/test/path/invoice_#{System.unique_integer([:positive])}.xml",
          blob_checksum: "cost-invoice-#{System.unique_integer([:positive])}",
          original_filename: "invoice.xml",
          organization_id: organization_id
        })

      assert {:error, %Ash.Error.Forbidden{}} =
               CostInvoice.update_blob_id(invoice, blob.id, scope: %Scope{actor: admin, tenant: organization_id})

      processor = %Firmowid.SystemActor{org_id: organization_id, role: :cost_invoice_processor}

      assert {:ok, %{blob_id: blob_id}} =
               CostInvoice.update_blob_id(invoice, blob.id, scope: %Scope{actor: processor, tenant: organization_id})

      assert blob_id == blob.id
    end
  end

  test "the cost invoice processor runs only the actions of its jobs" do
    organization_id = admin_fixture().member.organization_id
    invoice = insert_ksef_cost_invoice!(organization_id)
    actor = %Firmowid.SystemActor{org_id: organization_id, role: :cost_invoice_processor}
    opts = [tenant: organization_id]

    assert Ash.can?({invoice, :update_blob_id}, actor, opts)
    assert Ash.can?({invoice, :refresh_seller_display_name}, actor, opts)
    assert Ash.can?({CostInvoice, :create_from_ksef, %{}}, actor, opts)
    refute Ash.can?({invoice, :toggle_skip}, actor, opts)
    refute Ash.can?({invoice, :update_internal_note}, actor, opts)
    refute Ash.can?({invoice, :refresh_description}, actor, opts)

    # The AshOban default actor has no organization, and the global read is not among its actions.
    default_actor = %Firmowid.SystemActor{org_id: nil, role: :cost_invoice_processor}
    assert %{results: []} = CostInvoice.read_global!(actor: default_actor, page: [limit: 5])
  end

  describe "create" do
    test "persists a Money amount" do
      user = admin_fixture()
      scope = %Scope{actor: user, tenant: user.member.organization_id}

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
      scope = %Scope{actor: user, tenant: user.member.organization_id}

      original =
        insert_cost_invoice!(user.member.organization_id, %{
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
      scope = %Scope{actor: user, tenant: user.member.organization_id}

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
      scope = %Scope{actor: user, tenant: user.member.organization_id}

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
               Invoicing.create_cost_invoice_from_ksef(%{
                 organization_id: user.member.organization_id,
                 seller: "Supplier Sp. z o.o.",
                 sale_date: ~D[2026-02-01],
                 issue_date: ~D[2026-02-01],
                 items_list: [],
                 amount: Money.new!("PLN", "-100.00"),
                 invoice_identifier: "FV/2026/02/LATE-ORIGINAL",
                 ksef_number: "KSEF-LATE-ORIGINAL"
               })
    end

    test "falls back to the seller when the display name cannot be generated" do
      user = admin_fixture()
      scope = %Scope{actor: user, tenant: user.member.organization_id}
      previous_generator = Application.get_env(:firmowid, :seller_display_name_enrichment_module)

      Application.put_env(
        :firmowid,
        :seller_display_name_enrichment_module,
        __MODULE__.FailingSellerDisplayNameGenerator
      )

      on_exit(fn -> restore_env(:seller_display_name_enrichment_module, previous_generator) end)

      assert {:ok, invoice} =
               CostInvoice.create(
                 %{
                   seller: "Supplier Sp. z o.o.",
                   sale_date: ~D[2026-02-01],
                   issue_date: ~D[2026-02-01],
                   items_list: [],
                   amount: Money.new!("PLN", "-123.45"),
                   invoice_identifier: "FV/2026/02/NO-DISPLAY-NAME"
                 },
                 scope: scope
               )

      assert invoice.seller_display_name == "Supplier Sp. z o.o."

      named_invoice =
        insert_cost_invoice!(user.member.organization_id, %{seller_display_name: "Supplier"})

      assert {:ok, %{seller_display_name: "Supplier"}} =
               CostInvoice.refresh_seller_display_name(named_invoice, scope: scope)
    end

    test "rejects a positive non-correction amount" do
      user = admin_fixture()
      scope = %Scope{actor: user, tenant: user.member.organization_id}

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

      assert Exception.message(error) =~
               "must be <= 0 except for corrections and settlement invoices"
    end
  end

  describe "effective amount" do
    test "sums same-currency correction deltas as Money" do
      user = admin_fixture()
      scope = %Scope{actor: user, tenant: user.member.organization_id}

      original =
        insert_cost_invoice!(user.member.organization_id, %{
          ksef_number: "KSEF-EFFECTIVE-AMOUNT",
          amount: Money.new!("PLN", "-100.00")
        })

      insert_cost_invoice!(user.member.organization_id, %{
        invoice_type: :kor,
        original_invoice_ksef_number: original.ksef_number,
        amount: Money.new!("PLN", "20.00")
      })

      insert_cost_invoice!(user.member.organization_id, %{
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
      scope = %Scope{actor: user, tenant: user.member.organization_id}

      original =
        insert_cost_invoice!(user.member.organization_id, %{
          ksef_number: "KSEF-EFFECTIVE-MULTI-CURRENCY",
          amount: Money.new!("PLN", "-100.00")
        })

      insert_cost_invoice!(user.member.organization_id, %{
        invoice_type: :kor,
        original_invoice_ksef_number: original.ksef_number,
        amount: Money.new!("EUR", "10.00"),
        ksef_permanent_storage_date: ~N[2026-02-01 12:00:00]
      })

      insert_cost_invoice!(user.member.organization_id, %{
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
      scope = %Scope{actor: user, tenant: user.member.organization_id}

      original =
        insert_cost_invoice!(user.member.organization_id, %{amount: Money.new!("PLN", "-100.00")})

      insert_cost_invoice!(user.member.organization_id, %{
        invoice_type: :kor,
        original_invoice_ksef_number: "KSEF-NOT-PRESENT",
        amount: Money.new!("PLN", "20.00")
      })

      invoice = Ash.load!(original, [:effective_amount], scope: scope)

      assert Money.to_decimal(invoice.effective_amount) == Decimal.new("-100.00")
    end

    test "filters and sorts effective amounts in PostgreSQL" do
      user = admin_fixture()
      scope = %Scope{actor: user, tenant: user.member.organization_id}

      first_invoice =
        insert_cost_invoice!(user.member.organization_id, %{
          ksef_number: "KSEF-EFFECTIVE-QUERY-FIRST",
          amount: Money.new!("PLN", "-100.00")
        })

      second_invoice =
        insert_cost_invoice!(user.member.organization_id, %{
          ksef_number: "KSEF-EFFECTIVE-QUERY-SECOND",
          amount: Money.new!("PLN", "-100.00")
        })

      insert_cost_invoice!(user.member.organization_id, %{
        invoice_type: :kor,
        original_invoice_ksef_number: first_invoice.ksef_number,
        amount: Money.new!("PLN", "15.00")
      })

      insert_cost_invoice!(user.member.organization_id, %{
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
        |> then(&CostInvoice.list!(query: &1, scope: scope))

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
