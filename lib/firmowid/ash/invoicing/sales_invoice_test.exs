defmodule Firmowid.Ash.Invoicing.SalesInvoiceTest do
  @moduledoc false
  use Firmowid.DataCase

  import Firmowid.AccountsFixtures

  alias Ash.Error.Invalid
  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Invoicing.Counterparty
  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Ksef.Services.InvoiceRenderer
  alias Firmowid.Ash.Ksef.Workers.SubmissionWorker
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor
  alias Firmowid.InvoicingFixtures

  require Ash.Query

  describe "invoice number uniqueness" do
    test "allows multiple unnumbered drafts in the same organization" do
      user = admin_fixture()

      attrs =
        Map.merge(base_invoice_attrs(), %{
          invoice_number: nil,
          sales_invoice_items: [base_item_attrs(%{})]
        })

      first = create_sales_invoice!(user, attrs)
      second = create_sales_invoice!(user, attrs)

      assert first.id != second.id
      assert is_nil(first.invoice_number)
      assert is_nil(second.invoice_number)
      assert is_nil(first.locked_at)
      assert is_nil(second.locked_at)
    end

    test "rejects issuing a draft with a number already used in the organization" do
      user = invoicing_admin_fixture()
      InvoicingFixtures.connect_ksef!(user.organization_id)
      attrs = Map.put(base_invoice_attrs(), :sales_invoice_items, [base_item_attrs(%{})])
      issued = create_sales_invoice!(user, attrs)
      draft = create_sales_invoice!(user, %{attrs | invoice_number: nil})

      assert {:error, %Invalid{errors: errors}} =
               Oban.Testing.with_testing_mode(:manual, fn ->
                 Invoicing.issue_sales_invoice(draft, %{invoice_number: issued.invoice_number}, scope: scope_for(user))
               end)

      assert Enum.any?(
               errors,
               &match?(%Ash.Error.Changes.InvalidAttribute{field: :invoice_number}, &1)
             )
    end
  end

  describe "Money amounts" do
    test "read action filters invoice amounts through Money" do
      user = admin_fixture()
      scope = scope_for(user)

      eur_invoice =
        create_sales_invoice!(
          user,
          Map.put(base_invoice_attrs(), :sales_invoice_items, [base_item_attrs(%{})])
        )

      _pln_invoice =
        create_sales_invoice!(
          user,
          Map.merge(base_invoice_attrs(), %{
            invoice_number: "FV/#{System.unique_integer([:positive])}",
            currency: "PLN",
            sales_invoice_items: [base_item_attrs(%{unit_price: Decimal.new("200.00")})]
          })
        )

      invoices =
        Invoicing.list_sales_invoices!(
          %{currency: "EUR", amount_gt: Decimal.new("100.00"), amount_lt: Decimal.new("150.00")},
          scope: scope
        )

      assert Enum.map(invoices, & &1.id) == [eur_invoice.id]
    end

    test "derives the invoice amount from its Decimal item total and currency" do
      user = admin_fixture()

      invoice =
        create_sales_invoice!(
          user,
          Map.put(base_invoice_attrs(), :sales_invoice_items, [base_item_attrs(%{})])
        )

      invoice = Ash.load!(invoice, [:gross_value, :amount], scope: scope_for(user))

      assert Decimal.equal?(invoice.gross_value, Decimal.new("123.00"))
      assert Decimal.equal?(Money.to_decimal(invoice.amount), Decimal.new("123.00"))
      assert Money.to_currency_code(invoice.amount) == :EUR
    end

    test "uses the latest correction amount and currency as the effective amount" do
      user = admin_fixture()
      scope = scope_for(user)

      invoice =
        create_sales_invoice!(
          user,
          Map.put(base_invoice_attrs(), :sales_invoice_items, [base_item_attrs(%{})])
        )

      InvoicingFixtures.connect_ksef!(user.organization_id)

      assert {:ok, _correction} =
               Oban.Testing.with_testing_mode(:manual, fn ->
                 SalesInvoice.issue_correction(
                   %{
                     original_invoice_id: invoice.id,
                     invoice_number: "FK/#{System.unique_integer([:positive])}",
                     issue_date: ~D[2026-01-11],
                     currency: "PLN",
                     sales_invoice_items: [base_item_attrs(%{unit_price: Decimal.new("50")})]
                   },
                   scope: scope
                 )
               end)

      invoice = Ash.load!(invoice, [:effective_amount], scope: scope)

      assert Decimal.equal?(Money.to_decimal(invoice.effective_amount), Decimal.new("61.50"))
      assert Money.to_currency_code(invoice.effective_amount) == :PLN
    end

    test "keeps a zero-value invoice as Money" do
      user = admin_fixture()

      invoice =
        create_sales_invoice!(
          user,
          Map.put(base_invoice_attrs(), :sales_invoice_items, [
            base_item_attrs(%{quantity: Decimal.new(0)})
          ])
        )

      invoice = Ash.load!(invoice, [:amount], scope: scope_for(user))

      assert Decimal.equal?(Money.to_decimal(invoice.amount), Decimal.new(0))
      assert Money.to_currency_code(invoice.amount) == :EUR
    end

    test "filters and sorts derived Money amounts in PostgreSQL" do
      user = admin_fixture()
      scope = scope_for(user)

      lower_amount_invoice =
        create_sales_invoice!(
          user,
          Map.put(base_invoice_attrs(), :sales_invoice_items, [base_item_attrs(%{})])
        )

      higher_amount_invoice =
        create_sales_invoice!(
          user,
          Map.put(
            base_invoice_attrs(),
            :sales_invoice_items,
            [base_item_attrs(%{unit_price: Decimal.new("200")})]
          )
        )

      invoices =
        SalesInvoice
        |> Ash.Query.filter(amount > ^Money.new!("EUR", Decimal.new("100")))
        |> Ash.Query.sort(amount: :desc)
        |> Ash.Query.load(:amount)
        |> then(&SalesInvoice.list!(query: &1, scope: scope))

      assert Enum.map(invoices, & &1.id) == [higher_amount_invoice.id, lower_amount_invoice.id]

      assert Enum.all?(Enum.zip(invoices, ["246.00", "123.00"]), fn {invoice, expected_amount} ->
               Decimal.equal?(Money.to_decimal(invoice.amount), Decimal.new(expected_amount))
             end)
    end
  end

  describe "by_share_token/2" do
    test "reads a shared invoice with the anonymous actor" do
      user = admin_fixture()
      token = "shared-#{System.unique_integer([:positive])}"

      invoice = locked_sales_invoice_fixture(user.organization_id, token)

      anonymous_scope = %Scope{
        actor: %SystemActor{org_id: nil, role: :anonymous},
        tenant: nil
      }

      assert {:ok, %SalesInvoice{id: invoice_id}} =
               SalesInvoice.by_share_token(token, scope: anonymous_scope)

      assert invoice_id == invoice.id
    end
  end

  describe "reverse charge VAT normalization" do
    test "normalizes item vat_rate to oo on create when reverse charge is enabled" do
      user = invoicing_admin_fixture()

      attrs =
        Map.merge(draft_attrs(), %{
          is_reverse_charge: true,
          sales_invoice_items: [
            base_item_attrs(%{index: 0, vat_rate: "23"}),
            base_item_attrs(%{index: 1, name: "Second item", vat_rate: "8"})
          ]
        })

      invoice = create_draft!(user, attrs)

      assert Enum.all?(invoice.sales_invoice_items, &(&1.vat_rate == "oo"))
    end

    test "normalizes item vat_rate to oo on update when reverse charge is enabled" do
      user = invoicing_admin_fixture()

      create_attrs =
        Map.put(draft_attrs(), :sales_invoice_items, [base_item_attrs(%{vat_rate: "23"})])

      invoice = create_draft!(user, create_attrs)

      [existing_item] = invoice.sales_invoice_items

      update_attrs = %{
        is_reverse_charge: true,
        sales_invoice_items: [
          %{
            id: existing_item.id,
            name: "Updated item",
            vat_rate: "5",
            quantity: 1,
            unit: "szt.",
            unit_price: 100
          }
        ]
      }

      updated_invoice = update_sales_invoice!(user, invoice, update_attrs)

      assert Enum.all?(updated_invoice.sales_invoice_items, &(&1.vat_rate == "oo"))
    end

    test "normalizes preloaded item vat_rate to oo when reverse charge flag is enabled via update" do
      user = invoicing_admin_fixture()

      create_attrs =
        Map.put(draft_attrs(), :sales_invoice_items, [base_item_attrs(%{vat_rate: "23"})])

      invoice = create_draft!(user, create_attrs)

      [existing_item] = invoice.sales_invoice_items

      updated =
        update_sales_invoice!(user, invoice, %{
          is_reverse_charge: true,
          sales_invoice_items: [
            %{
              id: existing_item.id,
              name: existing_item.name,
              quantity: existing_item.quantity,
              unit: existing_item.unit,
              unit_price: existing_item.unit_price,
              vat_rate: existing_item.vat_rate
            }
          ]
        })

      assert Enum.all?(updated.sales_invoice_items, &(&1.vat_rate == "oo"))
    end

    test "normalizes oo back to buyer-context rate when reverse charge is disabled" do
      user = invoicing_admin_fixture()

      create_attrs =
        Map.merge(draft_attrs(), %{
          is_reverse_charge: true,
          sales_invoice_items: [base_item_attrs(%{vat_rate: "oo"})]
        })

      invoice = create_draft!(user, create_attrs)
      assert Enum.all?(invoice.sales_invoice_items, &(&1.vat_rate == "oo"))

      [existing_item] = invoice.sales_invoice_items

      updated =
        update_sales_invoice!(user, invoice, %{
          is_reverse_charge: false,
          sales_invoice_items: [
            %{
              id: existing_item.id,
              name: existing_item.name,
              quantity: existing_item.quantity,
              unit: existing_item.unit,
              unit_price: existing_item.unit_price,
              vat_rate: "oo"
            }
          ]
        })

      # DE company maps to EU VAT context, so fallback is fixed "np II"
      assert Enum.all?(updated.sales_invoice_items, &(&1.vat_rate == "np II"))
    end
  end

  describe "toggle_skip_invoicing/1" do
    test "allows toggling skip_invoicing on locked invoices" do
      user = admin_fixture()
      invoice = locked_sales_invoice_fixture(user.organization_id)
      scope = scope_for(user)

      assert invoice.skip_invoicing == false

      updated_invoice = Invoicing.toggle_sales_invoice_skip!(invoice, scope: scope)

      assert updated_invoice.skip_invoicing == true

      refetched = Invoicing.get_sales_invoice!(invoice.id, scope: scope)
      assert refetched.skip_invoicing == true
    end
  end

  describe "persisted KSeF lock" do
    test "rejects updates and item changes from a record read before locking" do
      user = invoicing_admin_fixture()
      scope = scope_for(user)

      invoice =
        create_draft!(user, Map.put(draft_attrs(), :sales_invoice_items, [base_item_attrs(%{})]))

      [item] = invoice.sales_invoice_items
      Invoicing.lock_sales_invoice_for_ksef!(invoice, scope: scope)

      assert {:error, %Invalid{}} =
               Invoicing.update_sales_invoice_draft(invoice, %{buyer_full_name: "Changed buyer"}, scope: scope)

      assert {:error, %Invalid{}} =
               invoice
               |> Ash.Changeset.for_update(
                 :denormalize_item_names,
                 %{item_names: "Changed item names"},
                 scope: scope
               )
               |> Ash.update(scope: scope)

      assert {:error, %Invalid{}} =
               Invoicing.update_sales_invoice_draft(
                 invoice,
                 %{sales_invoice_items: [%{id: item.id, name: "Changed item", unit_price: 500}]},
                 scope: scope
               )

      refetched =
        Invoicing.get_sales_invoice!(invoice.id, load: [:sales_invoice_items], scope: scope)

      assert refetched.buyer_full_name == invoice.buyer_full_name
      assert [%{name: name, unit_price: price}] = refetched.sales_invoice_items
      assert name == item.name
      assert Decimal.equal?(price, item.unit_price)
    end

    test "rejects deletion from a record read before locking" do
      user = admin_fixture()
      scope = scope_for(user)

      invoice =
        create_sales_invoice!(
          user,
          Map.put(base_invoice_attrs(), :sales_invoice_items, [base_item_attrs(%{})])
        )

      Invoicing.lock_sales_invoice_for_ksef!(invoice, scope: scope)

      assert {:error, %Invalid{}} = Invoicing.destroy_sales_invoice(invoice, scope: scope)
      assert Invoicing.get_sales_invoice!(invoice.id, scope: scope).locked_at
    end

    test "rejects deletion from a record read before receiving a KSeF number" do
      user = admin_fixture()
      scope = scope_for(user)

      invoice =
        create_sales_invoice!(
          user,
          Map.put(base_invoice_attrs(), :sales_invoice_items, [base_item_attrs(%{})])
        )

      Invoicing.update_sales_invoice_ksef_fields!(
        invoice,
        %{ksef_number: "5261040828-20260110-ABCDEF123456-AB"},
        scope: scope
      )

      assert {:error, %Invalid{}} = Invoicing.destroy_sales_invoice(invoice, scope: scope)
      assert Invoicing.get_sales_invoice!(invoice.id, scope: scope).ksef_number
    end
  end

  describe "attach_suggested_counterparty/2" do
    for ksef_number <- [nil, "5261040828-20260110-ABCDEF123456-AB"] do
      @ksef_number ksef_number

      test "allows internal attachment without changing KSeF XML when ksef_number is #{inspect(ksef_number)}" do
        user = admin_fixture()
        scope = scope_for(user)

        invoice =
          user
          |> create_sales_invoice!(Map.put(base_invoice_attrs(), :sales_invoice_items, [base_item_attrs(%{})]))
          |> Ash.Seed.update!(%{locked_at: DateTime.utc_now(:second), ksef_number: @ksef_number})

        original_xml = issued_invoice_xml(invoice, scope)

        counterparty = company_counterparty_fixture(user, %{tax_id: "DE123456789", country: "DE"})

        assert {:ok, updated} =
                 Invoicing.attach_suggested_sales_invoice_counterparty(
                   invoice,
                   counterparty.id,
                   scope: scope
                 )

        refetched = Invoicing.get_sales_invoice!(updated.id, scope: scope)
        assert refetched.counterparty_id == counterparty.id
        assert refetched.locked_at == invoice.locked_at
        assert refetched.ksef_number == invoice.ksef_number
        assert issued_invoice_xml(refetched, scope) == original_xml

        assert {:error, %Invalid{}} =
                 Invoicing.update_sales_invoice_draft(
                   refetched,
                   %{buyer_full_name: "Changed buyer"},
                   scope: scope
                 )

        assert {:error, %Invalid{}} = Invoicing.destroy_sales_invoice(refetched, scope: scope)
      end
    end

    test "rejects attach when invoice no longer matches suggestion predicate" do
      user = admin_fixture()
      scope = scope_for(user)

      counterparty = company_counterparty_fixture(user, %{tax_id: "DE123456789", country: "DE"})

      non_matching_invoice =
        create_sales_invoice!(
          user,
          Map.merge(base_invoice_attrs(), %{
            buyer_id: "PL9999999999",
            buyer_country: "PL",
            buyer_type: :company,
            sales_invoice_items: [base_item_attrs(%{})]
          })
        )

      assert {:error, %Invalid{}} =
               Invoicing.attach_suggested_sales_invoice_counterparty(
                 non_matching_invoice,
                 counterparty.id,
                 scope: scope
               )

      refetched = Invoicing.get_sales_invoice!(non_matching_invoice.id, scope: scope)
      assert is_nil(refetched.counterparty_id)
    end

    test "rejects attaching already linked invoice to another counterparty" do
      user = admin_fixture()
      scope = scope_for(user)

      original_counterparty =
        company_counterparty_fixture(user, %{tax_id: "DE123456789", country: "DE"})

      other_counterparty =
        company_counterparty_fixture(user, %{tax_id: "DE987654321", country: "DE"})

      invoice =
        create_sales_invoice!(
          user,
          Map.merge(base_invoice_attrs(), %{
            buyer_id: "DE123456789",
            buyer_country: "DE",
            buyer_type: :company,
            counterparty_id: original_counterparty.id,
            sales_invoice_items: [base_item_attrs(%{})]
          })
        )

      assert {:error, %Invalid{}} =
               Invoicing.attach_suggested_sales_invoice_counterparty(
                 invoice,
                 other_counterparty.id,
                 scope: scope
               )

      refetched = Invoicing.get_sales_invoice!(invoice.id, scope: scope)
      assert refetched.counterparty_id == original_counterparty.id
    end
  end

  describe "issuance" do
    test "issues a draft saved on an earlier day with today's issue date and queues KSeF" do
      user = invoicing_admin_fixture()
      InvoicingFixtures.connect_ksef!(user.organization_id)

      draft =
        create_sales_invoice!(
          user,
          Map.merge(base_invoice_attrs(), %{
            invoice_number: nil,
            issue_date: Date.add(Date.utc_today(), -30),
            sales_invoice_items: [base_item_attrs(%{})]
          })
        )

      # Manual mode keeps the queued KSeF job from running against the API.
      assert {:ok, issued} =
               Oban.Testing.with_testing_mode(:manual, fn ->
                 Invoicing.issue_sales_invoice(
                   draft,
                   %{invoice_number: "FV/#{System.unique_integer([:positive])}"},
                   scope: scope_for(user)
                 )
               end)

      assert issued.id == draft.id
      assert issued.issue_date == Date.utc_today()
      assert issued.ksef_submission_status == :submitting
      assert_enqueued(worker: SubmissionWorker, args: %{"sales_invoice_id" => issued.id})
    end

    test "issues nothing without a KSeF connection" do
      user = invoicing_admin_fixture()

      assert {:error, %Invalid{}} =
               Invoicing.create_and_issue_sales_invoice(
                 %{input: Map.put(issue_input(), :invoice_number, "FV/1/2026")},
                 scope: scope_for(user)
               )

      assert [] = Invoicing.list_sales_invoices!(scope: scope_for(user))
    end

    test "issues each confirmation only once" do
      user = invoicing_admin_fixture()
      InvoicingFixtures.connect_ksef!(user.organization_id)
      confirmation_id = Ash.UUIDv7.generate()

      attrs = %{
        input: Map.put(issue_input(), :invoice_number, "FV/#{System.unique_integer([:positive])}"),
        confirmation_id: confirmation_id
      }

      {first_attempt, second_attempt} =
        Oban.Testing.with_testing_mode(:manual, fn ->
          {Invoicing.create_and_issue_sales_invoice(attrs, scope: scope_for(user)),
           Invoicing.create_and_issue_sales_invoice(
             put_in(attrs.input.invoice_number, "FV/#{System.unique_integer([:positive])}"),
             scope: scope_for(user)
           )}
        end)

      assert {:ok, %{id: ^confirmation_id}} = first_attempt

      assert {:error, %Invalid{}} = second_attempt
      assert [_issued] = Invoicing.list_sales_invoices!(scope: scope_for(user))
    end

    test "points to organization settings when seller details are missing" do
      user = admin_fixture()

      assert {:error, %Invalid{errors: errors}} =
               Invoicing.create_sales_invoice_draft(%{input: issue_input()},
                 scope: scope_for(user)
               )

      assert %{message: "Uzupełnij adres firmy w ustawieniach organizacji."} =
               Enum.find(errors, &match?(%{field: :seller_address}, &1))
    end
  end

  defp invoicing_admin_fixture do
    user = admin_fixture()

    user.organization_id
    |> Firmowid.Ash.Core.get_organization!(actor: user, tenant: user.organization_id)
    |> Ash.Seed.update!(%{address: "ul. Testowa 1, 00-001 Warszawa"})

    user
  end

  defp create_draft!(user, attrs) do
    user
    |> scope_for()
    |> then(&Invoicing.create_sales_invoice_draft!(attrs, scope: &1))
    |> Ash.load!([:sales_invoice_items], scope: scope_for(user))
  end

  defp update_sales_invoice!(user, invoice, attrs) do
    updated = Invoicing.update_sales_invoice_draft!(invoice, attrs, scope: scope_for(user))
    Ash.load!(updated, [:sales_invoice_items], scope: scope_for(user))
  end

  defp draft_attrs do
    Map.drop(base_invoice_attrs(), [
      :invoice_number,
      :issue_date,
      :seller_nip,
      :seller_display_name,
      :seller_address,
      :ksef_invoice_kind
    ])
  end

  defp issue_input do
    base_invoice_attrs()
    |> Map.drop([
      :invoice_number,
      :seller_nip,
      :seller_display_name,
      :seller_address,
      :ksef_invoice_kind
    ])
    |> Map.put(:sales_invoice_items, [base_item_attrs(%{})])
  end

  defp scope_for(user), do: %Scope{actor: user, tenant: user.organization_id}

  defp issued_invoice_xml(invoice, scope) do
    # The renderer generates a fresh timestamp on each call; compare the issued content.
    invoice
    |> InvoiceRenderer.render_fa3(scope: scope)
    |> String.replace(~r/<DataWytworzeniaFa>[^<]+<\/DataWytworzeniaFa>/, "")
  end

  defp create_sales_invoice!(user, attrs) do
    invoice = InvoicingFixtures.seed_sales_invoice!(attrs, scope: scope_for(user))
    Ash.load!(invoice, [:sales_invoice_items], scope: scope_for(user))
  end

  defp base_invoice_attrs do
    %{
      invoice_type: :foreign,
      invoice_number: "FV/#{System.unique_integer([:positive])}",
      sale_date: ~D[2026-01-10],
      issue_date: ~D[2026-01-10],
      due_date: ~D[2026-01-24],
      payment_method: :transfer,
      currency: "EUR",
      seller_nip: "1234567890",
      seller_display_name: "Seller Sp. z o.o.",
      seller_address: "ul. Testowa 1, 00-001 Warszawa",
      seller_account_number: "12345678901234567890123456",
      buyer_type: :company,
      buyer_id: "DE123456789",
      buyer_full_name: "Buyer GmbH",
      buyer_address: "Teststrasse 1, 10115 Berlin",
      buyer_country: "DE",
      ksef_invoice_kind: :vat
    }
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

  defp locked_sales_invoice_fixture(organization_id, share_token \\ nil) do
    Ash.Seed.seed!(SalesInvoice, %{
      invoice_number: "FV/01/2026",
      sale_date: ~D[2026-01-01],
      issue_date: ~D[2026-01-01],
      due_date: ~D[2026-01-15],
      payment_method: :transfer,
      currency: "PLN",
      buyer_type: :company,
      buyer_id: "1234567890",
      buyer_full_name: "Test Buyer",
      buyer_address: "ul. Testowa 1",
      buyer_country: "PL",
      seller_display_name: "Test Seller",
      seller_nip: "1234567890",
      seller_address: "ul. Sprzedawcy 2",
      organization_id: organization_id,
      locked_at: DateTime.utc_now(:second),
      share_token: share_token
    })
  end

  defp company_counterparty_fixture(user, overrides) do
    attrs =
      Map.merge(
        %{
          type: :company,
          tax_id: "DE123456789",
          full_name: "Counterparty GmbH",
          address: "Counterpartystrasse 1, 10115 Berlin",
          country: "DE"
        },
        overrides
      )

    Ash.Seed.seed!(Counterparty, Map.put(attrs, :organization_id, user.organization_id))
  end
end
