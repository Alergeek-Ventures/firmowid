defmodule Firmowid.Ash.Ksef.KsefTestHelpers do
  @moduledoc """
  Helpers for KSeF FA(3) XSD validation in tests.

  Downloads and caches external XSD schemas from gov.pl,
  compiles the FA(3) schema with erlsom, and provides
  validation and invoice fixture functions.

  All fixture functions use `Ash.Seed.seed!` to create real database records
  through the Ash resource layer, ensuring tests validate the full integration
  path from resource to XML rendering.

  All `build_*` functions require an `org_id:` keyword option specifying the
  organization UUID to use for the seeded records.
  """
  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Invoicing.SalesInvoiceItem
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor

  # erlsom is a test-only dependency, suppress undefined module warning in non-test envs
  @compile {:no_warn_undefined, [:erlsom]}

  @schema_cache_dir Path.join([:code.priv_dir(:firmowid), "ksef_schemas"])

  @base_url "http://crd.gov.pl/xml/schematy/dziedzinowe/mf/2022/01/05/eD/DefinicjeTypy"

  @external_schemas [
    {"schemat.xsd", "http://crd.gov.pl/wzor/2025/06/25/13775/schemat.xsd"},
    {"KodyKrajow_v10-0E.xsd", "#{@base_url}/KodyKrajow_v10-0E.xsd"},
    {"ElementarneTypyDanych_v10-0E.xsd", "#{@base_url}/ElementarneTypyDanych_v10-0E.xsd"},
    {"StrukturyDanych_v10-0E.xsd", "#{@base_url}/StrukturyDanych_v10-0E.xsd"}
  ]

  @doc "Generates a unique invoice number with an optional prefix."
  @spec unique_invoice_number(String.t()) :: String.t()
  def unique_invoice_number(prefix \\ "") do
    id = System.unique_integer([:positive])
    "#{prefix}#{id}/01/2026"
  end

  @doc "Downloads and caches external XSD schemas from gov.pl for FA(3) validation."
  @spec ensure_schemas_cached!() :: :ok
  # sobelow_skip ["Traversal.FileModule"]
  # path is constructed from @schema_cache_dir (priv/ksef_schemas), not user input.
  # This caches external XSD schemas for FA(3) validation in tests.
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

  @doc "Compiles the FA(3) XSD schema with erlsom. Returns the compiled model."
  @spec compile_ksef_schema!() :: term()
  def compile_ksef_schema! do
    schema_path = Path.join(@schema_cache_dir, "schemat.xsd")
    charlist_path = String.to_charlist(schema_path)
    include_dir = String.to_charlist(@schema_cache_dir)

    # Use include_dirs option to tell erlsom where to find imported schemas
    case :erlsom.compile_xsd_file(charlist_path, include_dirs: [include_dir]) do
      {:ok, model} -> model
      {:error, reason} -> raise RuntimeError, "Failed to compile KSeF schema: #{inspect(reason)}"
    end
  end

  @doc "Validates XML against a compiled XSD model. Returns `:ok` or `{:error, reason}`."
  @spec validate_xml(binary(), term()) :: :ok | {:error, term()}
  def validate_xml(xml, model) when is_binary(xml) do
    case :erlsom.scan(xml, model) do
      {:ok, _record, _rest} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Builds a domestic VAT invoice fixture with configurable rate, items, and buyer.

  Requires `org_id:` in opts.
  """
  @spec build_domestic_invoice(keyword()) :: map()
  def build_domestic_invoice(opts \\ []) do
    org_id = Keyword.fetch!(opts, :org_id)
    vat_rate = Keyword.get(opts, :vat_rate, "23")
    item_count = Keyword.get(opts, :items, 1)

    invoice =
      Ash.Seed.seed!(SalesInvoice, %{
        invoice_number: unique_invoice_number(),
        issue_date: ~D[2026-01-15],
        sale_date: Keyword.get(opts, :sale_date, ~D[2026-01-15]),
        due_date: ~D[2026-01-30],
        currency: "PLN",
        payment_method: :transfer,
        seller_nip: "1234567890",
        seller_display_name: "Test Seller Sp. z o.o.",
        seller_address: "ul. Testowa 1, 00-001 Warszawa",
        seller_account_number: "12345678901234567890123456",
        buyer_type: :company,
        buyer_id: "9876543210",
        buyer_full_name: Keyword.get(opts, :buyer_name, "Test Buyer S.A."),
        buyer_address: Keyword.get(opts, :buyer_address, "ul. Kupiecka 2, 00-002 Krakow"),
        buyer_country: "PL",
        is_reverse_charge: false,
        ksef_invoice_kind: :vat,
        invoice_type: :poland,
        organization_id: org_id
      })

    seed_items!(invoice, build_item_attrs(item_count, vat_rate, opts))

    Ash.load!(
      invoice,
      [sales_invoice_items: [:net_value, :vat_value, :gross_value]],
      load_opts(invoice.organization_id)
    )
  end

  @doc """
  Builds a multi-rate invoice fixture with items at 23%, 8%, and 5% VAT.

  Requires `org_id:` in opts.
  """
  @spec build_multi_rate_invoice(keyword()) :: map()
  def build_multi_rate_invoice(opts \\ []) do
    org_id = Keyword.fetch!(opts, :org_id)

    invoice =
      Ash.Seed.seed!(SalesInvoice, %{
        invoice_number: unique_invoice_number(),
        issue_date: ~D[2026-01-15],
        sale_date: ~D[2026-01-15],
        due_date: ~D[2026-01-30],
        currency: "PLN",
        payment_method: :transfer,
        seller_nip: "1234567890",
        seller_display_name: "Test Seller Sp. z o.o.",
        seller_address: "ul. Testowa 1, 00-001 Warszawa",
        seller_account_number: "12345678901234567890123456",
        buyer_type: :company,
        buyer_id: "9876543210",
        buyer_full_name: Keyword.get(opts, :buyer_name, "Test Buyer S.A."),
        buyer_address: "ul. Kupiecka 2, 00-002 Krakow",
        buyer_country: "PL",
        is_reverse_charge: false,
        ksef_invoice_kind: :vat,
        invoice_type: :poland,
        organization_id: org_id
      })

    items = [
      %{
        name: "Service at 23%",
        quantity: Decimal.new("1"),
        unit: "szt.",
        unit_price: Decimal.new("100.00"),
        vat_rate: "23"
      },
      %{
        name: "Service at 8%",
        quantity: Decimal.new("1"),
        unit: "szt.",
        unit_price: Decimal.new("100.00"),
        vat_rate: "8"
      },
      %{
        name: "Service at 5%",
        quantity: Decimal.new("1"),
        unit: "szt.",
        unit_price: Decimal.new("100.00"),
        vat_rate: "5"
      }
    ]

    seed_items!(invoice, items)

    Ash.load!(
      invoice,
      [sales_invoice_items: [:net_value, :vat_value, :gross_value]],
      load_opts(invoice.organization_id)
    )
  end

  @doc """
  Builds a reverse charge (oo) invoice fixture for EU B2B.

  Requires `org_id:` in opts.
  """
  @spec build_reverse_charge_invoice(keyword()) :: map()
  def build_reverse_charge_invoice(opts \\ []) do
    org_id = Keyword.fetch!(opts, :org_id)

    invoice =
      Ash.Seed.seed!(SalesInvoice, %{
        invoice_type: :foreign,
        invoice_number: unique_invoice_number(),
        issue_date: ~D[2026-01-15],
        sale_date: ~D[2026-01-15],
        due_date: ~D[2026-01-30],
        currency: Keyword.get(opts, :currency, "EUR"),
        payment_method: :transfer,
        seller_nip: "1234567890",
        seller_display_name: "Test Seller Sp. z o.o.",
        seller_address: "ul. Testowa 1, 00-001 Warszawa",
        seller_account_number: "12345678901234567890123456",
        buyer_type: :company,
        buyer_id: "123456789",
        buyer_full_name: "German Client GmbH",
        buyer_address: "Teststrasse 1, 10115 Berlin",
        buyer_country: "DE",
        is_reverse_charge: true,
        ksef_invoice_kind: :vat,
        organization_id: org_id
      })

    seed_items!(invoice, [
      %{
        name: "Software Development Services",
        quantity: Decimal.new("40"),
        unit: "h",
        unit_price: Decimal.new("100.00"),
        vat_rate: "oo"
      }
    ])

    Ash.load!(
      invoice,
      [sales_invoice_items: [:net_value, :vat_value, :gross_value]],
      load_opts(invoice.organization_id)
    )
  end

  @doc """
  Builds an EU VAT invoice fixture with French buyer and standard 23% rate.

  Requires `org_id:` in opts.
  """
  @spec build_eu_vat_invoice(keyword()) :: map()
  def build_eu_vat_invoice(opts \\ []) do
    org_id = Keyword.fetch!(opts, :org_id)

    invoice =
      Ash.Seed.seed!(SalesInvoice, %{
        invoice_number: unique_invoice_number(),
        issue_date: ~D[2026-01-15],
        sale_date: ~D[2026-01-15],
        due_date: ~D[2026-01-30],
        currency: "PLN",
        payment_method: :transfer,
        seller_nip: "1234567890",
        seller_display_name: "Test Seller Sp. z o.o.",
        seller_address: "ul. Testowa 1, 00-001 Warszawa",
        seller_account_number: "12345678901234567890123456",
        buyer_type: :company,
        buyer_id: "12345678901",
        buyer_full_name: Keyword.get(opts, :buyer_name, "French Company SARL"),
        buyer_address: "1 Rue de Test, 75001 Paris",
        buyer_country: "FR",
        is_reverse_charge: false,
        ksef_invoice_kind: :vat,
        invoice_type: :poland,
        organization_id: org_id
      })

    seed_items!(invoice, [
      %{
        name: "Consulting Services",
        quantity: Decimal.new("10"),
        unit: "h",
        unit_price: Decimal.new("150.00"),
        vat_rate: "23"
      }
    ])

    Ash.load!(
      invoice,
      [sales_invoice_items: [:net_value, :vat_value, :gross_value]],
      load_opts(invoice.organization_id)
    )
  end

  @doc """
  Builds an invoice fixture with a non-EU buyer (US) using NrID identification.

  Uses `oo` (reverse charge) VAT rate to test the renderer's handling of the
  combination, even though the correct business rate for US buyers is `np I`.

  Requires `org_id:` in opts.
  """
  @spec build_other_id_invoice(keyword()) :: map()
  def build_other_id_invoice(opts \\ []) do
    org_id = Keyword.fetch!(opts, :org_id)

    invoice =
      Ash.Seed.seed!(SalesInvoice, %{
        invoice_type: :foreign,
        invoice_number: unique_invoice_number(),
        issue_date: ~D[2026-01-15],
        sale_date: ~D[2026-01-15],
        due_date: ~D[2026-01-30],
        currency: "USD",
        payment_method: :transfer,
        seller_nip: "1234567890",
        seller_display_name: "Test Seller Sp. z o.o.",
        seller_address: "ul. Testowa 1, 00-001 Warszawa",
        seller_account_number: "12345678901234567890123456",
        buyer_type: :company,
        buyer_id: "US123456789",
        buyer_full_name: Keyword.get(opts, :buyer_name, "US Corporation Inc."),
        buyer_address: "123 Main St, New York, NY 10001",
        buyer_country: "US",
        is_reverse_charge: true,
        ksef_invoice_kind: :vat,
        organization_id: org_id
      })

    seed_items!(invoice, [
      %{
        name: "Software License",
        quantity: Decimal.new("1"),
        unit: "szt.",
        unit_price: Decimal.new("5000.00"),
        vat_rate: "oo"
      }
    ])

    Ash.load!(
      invoice,
      [sales_invoice_items: [:net_value, :vat_value, :gross_value]],
      load_opts(invoice.organization_id)
    )
  end

  @doc """
  Builds an invoice fixture with an individual buyer (no tax ID, BrakID=1).

  Requires `org_id:` in opts.
  """
  @spec build_no_id_invoice(keyword()) :: map()
  def build_no_id_invoice(opts \\ []) do
    org_id = Keyword.fetch!(opts, :org_id)

    invoice =
      Ash.Seed.seed!(SalesInvoice, %{
        invoice_number: unique_invoice_number(),
        issue_date: ~D[2026-01-15],
        sale_date: ~D[2026-01-15],
        due_date: ~D[2026-01-30],
        currency: "PLN",
        payment_method: :transfer,
        seller_nip: "1234567890",
        seller_display_name: "Test Seller Sp. z o.o.",
        seller_address: "ul. Testowa 1, 00-001 Warszawa",
        seller_account_number: "12345678901234567890123456",
        buyer_type: :individual,
        buyer_id: nil,
        buyer_given_name: Keyword.get(opts, :buyer_first_name, "Jan"),
        buyer_surname: Keyword.get(opts, :buyer_last_name, "Kowalski"),
        buyer_address: Keyword.get(opts, :buyer_address, "ul. Prywatna 5, 00-005 Warszawa"),
        buyer_country: "PL",
        is_reverse_charge: false,
        ksef_invoice_kind: :vat,
        invoice_type: :poland,
        organization_id: org_id
      })

    seed_items!(invoice, [
      %{
        name: "Retail Service",
        quantity: Decimal.new("1"),
        unit: "szt.",
        unit_price: Decimal.new("200.00"),
        vat_rate: "23"
      }
    ])

    Ash.load!(
      invoice,
      [sales_invoice_items: [:net_value, :vat_value, :gross_value]],
      load_opts(invoice.organization_id)
    )
  end

  @doc "Simulates KSeF submission by locking the invoice and optionally assigning a KSeF number."
  @spec simulate_ksef_submission(map(), keyword()) :: map()
  def simulate_ksef_submission(invoice, opts \\ []) do
    ksef_number =
      if Keyword.get(opts, :with_ksef_number, false) do
        # KSeF number format: NIP-DATE-HEXHEX-HEXHEX-HEX
        hex = 8 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :upper)

        "1234567890-20260115-#{String.slice(hex, 0, 6)}-#{String.slice(hex, 6, 6)}-#{String.slice(hex, 12, 2)}"
      end

    Ash.Seed.update!(invoice, %{locked_at: DateTime.utc_now(), ksef_number: ksef_number})
  end

  @doc "Builds a correction (KOR) invoice fixture referencing the given original invoice."
  @spec build_correction_invoice(map(), keyword()) :: map()
  def build_correction_invoice(original, opts \\ []) do
    correction =
      Ash.Seed.seed!(SalesInvoice, %{
        invoice_number: unique_invoice_number("KOR/"),
        issue_date: ~D[2026-01-20],
        sale_date: ~D[2026-01-15],
        due_date: ~D[2026-02-05],
        payment_method: original.payment_method,
        ksef_invoice_kind: :kor,
        corrected_invoice_id: original.id,
        # Copy fields from original
        invoice_type: original.invoice_type,
        currency: original.currency,
        seller_nip: original.seller_nip,
        seller_display_name: original.seller_display_name,
        seller_address: original.seller_address,
        seller_name: original.seller_name,
        seller_surname: original.seller_surname,
        seller_account_number: original.seller_account_number,
        buyer_type: original.buyer_type,
        buyer_id: original.buyer_id,
        buyer_full_name: original.buyer_full_name,
        buyer_given_name: original.buyer_given_name,
        buyer_surname: original.buyer_surname,
        buyer_display_name: original.buyer_display_name,
        buyer_address: original.buyer_address,
        buyer_country: original.buyer_country,
        buyer_is_different_mail_address: original.buyer_is_different_mail_address,
        buyer_mail_address: original.buyer_mail_address,
        buyer_mail_country: original.buyer_mail_country,
        buyer_email: original.buyer_email,
        buyer_phone: original.buyer_phone,
        buyer_description: original.buyer_description,
        buyer_pesel: original.buyer_pesel,
        is_reverse_charge: original.is_reverse_charge,
        is_cash_account: original.is_cash_account,
        counterparty_id: original.counterparty_id,
        organization_id: original.organization_id
      })

    items =
      Keyword.get(opts, :items, [
        %{
          name: "Corrected Service",
          quantity: Decimal.new("-1"),
          unit: "szt.",
          unit_price: Decimal.new("100.00"),
          vat_rate: "23"
        }
      ])

    seed_items!(correction, items)

    Ash.load!(
      correction,
      [:corrected_invoice, sales_invoice_items: [:net_value, :vat_value, :gross_value]],
      load_opts(correction.organization_id)
    )
  end

  defp load_opts(organization_id) do
    actor = %SystemActor{org_id: organization_id, role: :sales_invoice_processor}
    [scope: %Scope{actor: actor, tenant: organization_id}]
  end

  # Seeds invoice line items from a list of attribute maps.
  defp seed_items!(invoice, item_attrs) do
    item_attrs
    |> Enum.with_index()
    |> Enum.each(fn {attrs, index} ->
      Ash.Seed.seed!(
        SalesInvoiceItem,
        Map.merge(attrs, %{
          sales_invoice_id: invoice.id,
          organization_id: invoice.organization_id,
          index: index
        })
      )
    end)
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
        vat_rate: vat_rate
      }
    end
  end
end
