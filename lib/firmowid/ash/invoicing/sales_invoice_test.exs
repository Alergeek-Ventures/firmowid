defmodule Firmowid.Ash.Invoicing.SalesInvoiceTest do
  @moduledoc false
  use Firmowid.DataCase

  import Firmowid.AccountsFixtures

  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Invoicing.SalesInvoice

  # TODO: replace authorize?: false + actor: %{} with system actor once available
  @bridge_opts [authorize?: false, actor: %{}]

  describe "reverse charge VAT normalization" do
    test "normalizes item vat_rate to oo on create when reverse charge is enabled" do
      user = user_fixture()

      attrs =
        Map.merge(base_invoice_attrs(), %{
          is_reverse_charge: true,
          sales_invoice_items: [
            base_item_attrs(%{index: 0, vat_rate: "23"}),
            base_item_attrs(%{index: 1, name: "Second item", vat_rate: "8"})
          ]
        })

      invoice = create_sales_invoice!(user, attrs)

      assert Enum.all?(invoice.sales_invoice_items, &(&1.vat_rate == "oo"))
    end

    test "normalizes item vat_rate to oo on update when reverse charge is enabled" do
      user = user_fixture()

      create_attrs =
        Map.put(base_invoice_attrs(), :sales_invoice_items, [base_item_attrs(%{vat_rate: "23"})])

      invoice = create_sales_invoice!(user, create_attrs)

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
      user = user_fixture()

      create_attrs =
        Map.put(base_invoice_attrs(), :sales_invoice_items, [base_item_attrs(%{vat_rate: "23"})])

      invoice = create_sales_invoice!(user, create_attrs)

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
      user = user_fixture()

      create_attrs =
        Map.merge(base_invoice_attrs(), %{
          is_reverse_charge: true,
          sales_invoice_items: [base_item_attrs(%{vat_rate: "oo"})]
        })

      invoice = create_sales_invoice!(user, create_attrs)
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
      user = user_fixture()
      invoice = locked_sales_invoice_fixture(user.organization_id)
      opts = [tenant: user.organization_id] ++ @bridge_opts

      assert invoice.skip_invoicing == false

      updated_invoice = Invoicing.toggle_sales_invoice_skip!(invoice, opts)

      assert updated_invoice.skip_invoicing == true

      refetched = Invoicing.get_sales_invoice!(invoice.id, opts)
      assert refetched.skip_invoicing == true
    end
  end

  defp ash_opts(user) do
    [authorize?: false, actor: %{}, tenant: user.organization_id]
  end

  defp create_sales_invoice!(user, attrs) do
    invoice = Invoicing.create_sales_invoice!(attrs, ash_opts(user))
    Ash.load!(invoice, [:sales_invoice_items], ash_opts(user))
  end

  defp update_sales_invoice!(user, invoice, attrs) do
    updated = Invoicing.update_sales_invoice!(invoice, attrs, ash_opts(user))
    Ash.load!(updated, [:sales_invoice_items], ash_opts(user))
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

  defp locked_sales_invoice_fixture(organization_id) do
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
      locked_at: DateTime.utc_now(:second)
    })
  end
end
