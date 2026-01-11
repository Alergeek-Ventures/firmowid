defmodule Firmowid.KsefTestHelpers do
  @moduledoc """
  Helpers for KSeF FA(3) XSD validation in tests.

  Downloads and caches external XSD schemas from gov.pl,
  compiles the FA(3) schema with erlsom, and provides
  validation and invoice fixture functions.

  All fixture functions use the SalesInvoices context to create
  real database records, ensuring tests validate the full integration
  path from changeset to XML rendering.
  """

  alias Firmowid.Repo
  alias Firmowid.SalesInvoices
  alias Firmowid.SalesInvoices.SalesInvoice

  @schema_cache_dir Path.join([:code.priv_dir(:firmowid), "ksef_schemas"])

  @base_url "http://crd.gov.pl/xml/schematy/dziedzinowe/mf/2022/01/05/eD/DefinicjeTypy"

  @external_schemas [
    {"schemat.xsd", "http://crd.gov.pl/wzor/2025/06/25/13775/schemat.xsd"},
    {"KodyKrajow_v10-0E.xsd", "#{@base_url}/KodyKrajow_v10-0E.xsd"},
    {"ElementarneTypyDanych_v10-0E.xsd", "#{@base_url}/ElementarneTypyDanych_v10-0E.xsd"},
    {"StrukturyDanych_v10-0E.xsd", "#{@base_url}/StrukturyDanych_v10-0E.xsd"}
  ]

  def unique_invoice_number(prefix \\ "") do
    id = System.unique_integer([:positive])
    "#{prefix}#{id}/01/2026"
  end

  def ensure_schemas_cached! do
    File.mkdir_p!(@schema_cache_dir)

    # Download external schemas if not cached
    for {filename, url} <- @external_schemas do
      path = Path.join(@schema_cache_dir, filename)

      if !File.exists?(path) do
        response = Req.get!(url)
        content = localize_schema_refs(response.body)

        File.write!(path, content)
      end
    end

    :ok
  end

  def compile_ksef_schema! do
    schema_path = Path.join(@schema_cache_dir, "schemat.xsd")
    charlist_path = String.to_charlist(schema_path)
    include_dir = String.to_charlist(@schema_cache_dir)

    # Use include_dirs option to tell erlsom where to find imported schemas
    case :erlsom.compile_xsd_file(charlist_path, include_dirs: [include_dir]) do
      {:ok, model} -> model
      {:error, reason} -> raise "Failed to compile KSeF schema: #{inspect(reason)}"
    end
  end

  def validate_xml(xml, model) when is_binary(xml) do
    case :erlsom.scan(xml, model) do
      {:ok, _record, _rest} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def build_domestic_invoice(opts \\ []) do
    vat_rate = Keyword.get(opts, :vat_rate, 23)
    item_count = Keyword.get(opts, :items, 1)

    attrs = %{
      invoice_number: unique_invoice_number(),
      issue_date: ~D[2026-01-15],
      sale_date: Keyword.get(opts, :sale_date, ~D[2026-01-15]),
      due_date: ~D[2026-01-30],
      currency: "PLN",
      payment_method: "transfer",
      seller_nip: "1234567890",
      seller_display_name: "Test Seller Sp. z o.o.",
      seller_address: "ul. Testowa 1, 00-001 Warszawa",
      seller_account_number: "12345678901234567890123456",
      buyer_type: :company,
      buyer_id: "9876543210",
      buyer_display_name: Keyword.get(opts, :buyer_name, "Test Buyer S.A."),
      buyer_address: Keyword.get(opts, :buyer_address, "ul. Kupiecka 2, 00-002 Krakow"),
      buyer_country: "PL",
      is_reverse_charge: false,
      ksef_invoice_kind: :vat,
      sales_invoice_items: build_item_attrs(item_count, vat_rate, opts)
    }

    {:ok, invoice} = SalesInvoices.create_sales_invoice(%SalesInvoice{}, attrs)
    Repo.preload(invoice, :sales_invoice_items)
  end

  def build_multi_rate_invoice(opts \\ []) do
    attrs = %{
      invoice_number: unique_invoice_number(),
      issue_date: ~D[2026-01-15],
      sale_date: ~D[2026-01-15],
      due_date: ~D[2026-01-30],
      currency: "PLN",
      payment_method: "transfer",
      seller_nip: "1234567890",
      seller_display_name: "Test Seller Sp. z o.o.",
      seller_address: "ul. Testowa 1, 00-001 Warszawa",
      seller_account_number: "12345678901234567890123456",
      buyer_type: :company,
      buyer_id: "9876543210",
      buyer_display_name: Keyword.get(opts, :buyer_name, "Test Buyer S.A."),
      buyer_address: "ul. Kupiecka 2, 00-002 Krakow",
      buyer_country: "PL",
      is_reverse_charge: false,
      ksef_invoice_kind: :vat,
      sales_invoice_items: [
        %{
          name: "Service at 23%",
          quantity: Decimal.new("1"),
          unit: "szt.",
          unit_price: Decimal.new("100.00"),
          vat_rate: Decimal.new("23")
        },
        %{
          name: "Service at 8%",
          quantity: Decimal.new("1"),
          unit: "szt.",
          unit_price: Decimal.new("100.00"),
          vat_rate: Decimal.new("8")
        },
        %{
          name: "Service at 5%",
          quantity: Decimal.new("1"),
          unit: "szt.",
          unit_price: Decimal.new("100.00"),
          vat_rate: Decimal.new("5")
        }
      ]
    }

    {:ok, invoice} = SalesInvoices.create_sales_invoice(%SalesInvoice{}, attrs)
    Repo.preload(invoice, :sales_invoice_items)
  end

  def build_reverse_charge_invoice(opts \\ []) do
    attrs = %{
      invoice_type: :foreign,
      invoice_number: unique_invoice_number(),
      issue_date: ~D[2026-01-15],
      sale_date: ~D[2026-01-15],
      due_date: ~D[2026-01-30],
      currency: Keyword.get(opts, :currency, "EUR"),
      payment_method: "transfer",
      seller_nip: "1234567890",
      seller_display_name: "Test Seller Sp. z o.o.",
      seller_address: "ul. Testowa 1, 00-001 Warszawa",
      seller_account_number: "12345678901234567890123456",
      buyer_type: :company,
      buyer_id: "123456789",
      buyer_display_name: "German Client GmbH",
      buyer_address: "Teststrasse 1, 10115 Berlin",
      buyer_country: "DE",
      is_reverse_charge: true,
      ksef_invoice_kind: :vat,
      sales_invoice_items: [
        %{
          name: "Software Development Services",
          quantity: Decimal.new("40"),
          unit: "h",
          unit_price: Decimal.new("100.00"),
          vat_rate: Decimal.new("0")
        }
      ]
    }

    {:ok, invoice} = SalesInvoices.create_sales_invoice(%SalesInvoice{}, attrs)
    Repo.preload(invoice, :sales_invoice_items)
  end

  def build_eu_vat_invoice(opts \\ []) do
    attrs = %{
      invoice_number: unique_invoice_number(),
      issue_date: ~D[2026-01-15],
      sale_date: ~D[2026-01-15],
      due_date: ~D[2026-01-30],
      currency: "PLN",
      payment_method: "transfer",
      seller_nip: "1234567890",
      seller_display_name: "Test Seller Sp. z o.o.",
      seller_address: "ul. Testowa 1, 00-001 Warszawa",
      seller_account_number: "12345678901234567890123456",
      buyer_type: :company,
      buyer_id: "12345678901",
      buyer_display_name: Keyword.get(opts, :buyer_name, "French Company SARL"),
      buyer_address: "1 Rue de Test, 75001 Paris",
      buyer_country: "FR",
      is_reverse_charge: false,
      ksef_invoice_kind: :vat,
      sales_invoice_items: [
        %{
          name: "Consulting Services",
          quantity: Decimal.new("10"),
          unit: "h",
          unit_price: Decimal.new("150.00"),
          vat_rate: Decimal.new("23")
        }
      ]
    }

    {:ok, invoice} = SalesInvoices.create_sales_invoice(%SalesInvoice{}, attrs)
    Repo.preload(invoice, :sales_invoice_items)
  end

  def build_other_id_invoice(opts \\ []) do
    attrs = %{
      invoice_type: :foreign,
      invoice_number: unique_invoice_number(),
      issue_date: ~D[2026-01-15],
      sale_date: ~D[2026-01-15],
      due_date: ~D[2026-01-30],
      currency: "USD",
      payment_method: "transfer",
      seller_nip: "1234567890",
      seller_display_name: "Test Seller Sp. z o.o.",
      seller_address: "ul. Testowa 1, 00-001 Warszawa",
      seller_account_number: "12345678901234567890123456",
      buyer_type: :company,
      buyer_id: "US123456789",
      buyer_display_name: Keyword.get(opts, :buyer_name, "US Corporation Inc."),
      buyer_address: "123 Main St, New York, NY 10001",
      buyer_country: "US",
      is_reverse_charge: true,
      ksef_invoice_kind: :vat,
      sales_invoice_items: [
        %{
          name: "Software License",
          quantity: Decimal.new("1"),
          unit: "szt.",
          unit_price: Decimal.new("5000.00"),
          vat_rate: Decimal.new("0")
        }
      ]
    }

    {:ok, invoice} = SalesInvoices.create_sales_invoice(%SalesInvoice{}, attrs)
    Repo.preload(invoice, :sales_invoice_items)
  end

  def build_no_id_invoice(opts \\ []) do
    attrs = %{
      invoice_number: unique_invoice_number(),
      issue_date: ~D[2026-01-15],
      sale_date: ~D[2026-01-15],
      due_date: ~D[2026-01-30],
      currency: "PLN",
      payment_method: "transfer",
      seller_nip: "1234567890",
      seller_display_name: "Test Seller Sp. z o.o.",
      seller_address: "ul. Testowa 1, 00-001 Warszawa",
      seller_account_number: "12345678901234567890123456",
      buyer_type: :individual,
      buyer_id: nil,
      buyer_name: Keyword.get(opts, :buyer_first_name, "Jan"),
      buyer_surname: Keyword.get(opts, :buyer_last_name, "Kowalski"),
      buyer_display_name: nil,
      buyer_address: Keyword.get(opts, :buyer_address, "ul. Prywatna 5, 00-005 Warszawa"),
      buyer_country: "PL",
      is_reverse_charge: false,
      ksef_invoice_kind: :vat,
      sales_invoice_items: [
        %{
          name: "Retail Service",
          quantity: Decimal.new("1"),
          unit: "szt.",
          unit_price: Decimal.new("200.00"),
          vat_rate: Decimal.new("23")
        }
      ]
    }

    {:ok, invoice} = SalesInvoices.create_sales_invoice(%SalesInvoice{}, attrs)
    Repo.preload(invoice, :sales_invoice_items)
  end

  def simulate_ksef_submission(invoice, opts \\ []) do
    ksef_number =
      if Keyword.get(opts, :with_ksef_number, false) do
        # KSeF number format: NIP-DATE-HEXHEX-HEXHEX-HEX
        "1234567890-20260115-A1B2C3-D4E5F6-78"
      end

    {:ok, updated} =
      invoice
      |> SalesInvoice.ksef_update_changeset(%{
        locked_at: DateTime.utc_now(),
        ksef_number: ksef_number
      })
      |> Repo.update()

    updated
  end

  def build_correction_invoice(original, opts \\ []) do
    attrs = %{
      invoice_number: unique_invoice_number("KOR/"),
      issue_date: ~D[2026-01-20],
      sale_date: ~D[2026-01-15],
      due_date: ~D[2026-02-05],
      payment_method: original.payment_method,
      sales_invoice_items:
        Keyword.get(opts, :items, [
          %{
            name: "Corrected Service",
            quantity: Decimal.new("-1"),
            unit: "szt.",
            unit_price: Decimal.new("100.00"),
            vat_rate: Decimal.new("23")
          }
        ])
    }

    {:ok, correction} = SalesInvoices.create_correction_invoice(original, attrs)
    Repo.preload(correction, [:sales_invoice_items, :corrected_invoice])
  end

  defp localize_schema_refs(content) do
    content
    |> String.replace(
      ~s|schemaLocation="#{@base_url}/KodyKrajow_v10-0E.xsd"|,
      ~s|schemaLocation="KodyKrajow_v10-0E.xsd"|
    )
    |> String.replace(
      ~s|schemaLocation="#{@base_url}/ElementarneTypyDanych_v10-0E.xsd"|,
      ~s|schemaLocation="ElementarneTypyDanych_v10-0E.xsd"|
    )
    |> String.replace(
      ~s|schemaLocation="#{@base_url}/StrukturyDanych_v10-0E.xsd"|,
      ~s|schemaLocation="StrukturyDanych_v10-0E.xsd"|
    )
  end

  defp build_item_attrs(count, vat_rate, opts) do
    item_name = Keyword.get(opts, :item_name, "Usluga programistyczna")
    quantity = Keyword.get(opts, :quantity, Decimal.new("1"))

    for i <- 1..count do
      %{
        name: if(count > 1, do: "#{item_name} #{i}", else: item_name),
        quantity: quantity,
        unit: "szt.",
        unit_price: Decimal.new("100.00"),
        vat_rate: Decimal.new(vat_rate)
      }
    end
  end
end
