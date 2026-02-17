defmodule Firmowid.SalesInvoicesTest do
  use Firmowid.DataCase

  import Firmowid.AccountsFixtures

  alias Firmowid.SalesInvoices
  alias Firmowid.SalesInvoices.SalesInvoice
  alias Firmowid.SalesInvoices.SalesInvoiceItem

  describe "reverse charge VAT normalization" do
    test "normalizes item vat_rate to oo on create when reverse charge is enabled" do
      _user = user_fixture()

      attrs =
        Map.merge(base_invoice_attrs(), %{
          is_reverse_charge: true,
          sales_invoice_items: [
            base_item_attrs(%{vat_rate: "23"}),
            base_item_attrs(%{name: "Second item", vat_rate: "8"})
          ]
        })

      assert {:ok, invoice} = SalesInvoices.create_sales_invoice(%SalesInvoice{}, attrs)

      assert Enum.all?(invoice.sales_invoice_items, &(&1.vat_rate == "oo"))
    end

    test "normalizes item vat_rate to oo on update when reverse charge is enabled" do
      _user = user_fixture()

      create_attrs = Map.put(base_invoice_attrs(), :sales_invoice_items, [base_item_attrs(%{vat_rate: "23"})])

      assert {:ok, invoice} = SalesInvoices.create_sales_invoice(%SalesInvoice{}, create_attrs)

      update_attrs = %{
        is_reverse_charge: true,
        sales_invoice_items: [
          base_item_attrs(%{name: "Updated item", vat_rate: "5"})
        ]
      }

      assert {:ok, updated_invoice} = SalesInvoices.update_sales_invoice(invoice, update_attrs)

      assert Enum.all?(updated_invoice.sales_invoice_items, &(&1.vat_rate == "oo"))
    end

    test "normalizes preloaded item vat_rate to oo when only reverse charge flag changes" do
      _user = user_fixture()

      invoice =
        %SalesInvoice{}
        |> SalesInvoice.changeset(
          Map.put(base_invoice_attrs(), :sales_invoice_items, [base_item_attrs(%{vat_rate: "23"})])
        )
        |> Firmowid.Repo.insert!()
        |> Firmowid.Repo.preload(:sales_invoice_items)

      changeset = SalesInvoice.changeset(invoice, %{is_reverse_charge: true})
      assert {:ok, preview_invoice} = Ecto.Changeset.apply_action(changeset, :update)

      assert Enum.all?(preview_invoice.sales_invoice_items, fn %SalesInvoiceItem{vat_rate: vat_rate} ->
               vat_rate == "oo"
             end)
    end

    test "normalizes nested params so form reflects oo immediately" do
      attrs = %{
        "currency" => "EUR",
        "is_reverse_charge" => "true",
        "sales_invoice_items" => %{
          "0" => %{
            "name" => "Programming service",
            "quantity" => "1",
            "unit" => "szt.",
            "unit_price" => "100.00",
            "vat_rate" => "23"
          }
        }
      }

      changeset = SalesInvoice.step2_changeset(%SalesInvoice{}, attrs)

      assert get_in(changeset.params, ["sales_invoice_items", "0", "vat_rate"]) == "oo"
      assert {:ok, preview_invoice} = Ecto.Changeset.apply_action(changeset, :update)
      assert Enum.all?(preview_invoice.sales_invoice_items, &(&1.vat_rate == "oo"))
    end

    test "normalizes oo back to buyer-context rate when reverse charge is disabled" do
      _user = user_fixture()

      invoice =
        %SalesInvoice{}
        |> SalesInvoice.changeset(
          Map.merge(base_invoice_attrs(), %{
            is_reverse_charge: true,
            sales_invoice_items: [base_item_attrs(%{vat_rate: "oo"})]
          })
        )
        |> Firmowid.Repo.insert!()
        |> Firmowid.Repo.preload(:sales_invoice_items)

      changeset = SalesInvoice.changeset(invoice, %{is_reverse_charge: false})
      assert {:ok, preview_invoice} = Ecto.Changeset.apply_action(changeset, :update)

      # DE company maps to EU VAT context, so fallback is fixed "np II"
      assert Enum.all?(preview_invoice.sales_invoice_items, &(&1.vat_rate == "np II"))
    end
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
      name: "Programming service",
      quantity: Decimal.new("1"),
      unit: "szt.",
      unit_price: Decimal.new("100.00"),
      vat_rate: "23"
    })
  end
end
