defmodule Firmowid.Test.Support.SalesInvoiceEmailTestHelpers do
  @moduledoc """
  Shared fixtures and assertions for sales invoice email flow tests.
  """

  import ExUnit.Assertions
  import ExUnit.Callbacks

  alias Firmowid.Ash.Invoicing.SalesInvoiceEmailDelivery
  alias Firmowid.Ash.Invoicing.Services.Pdf
  alias Firmowid.Ash.Invoicing.Workers.SalesInvoiceEmailWorker

  require Ash.Query

  @oban_test_opts [repo: Firmowid.Repo, prefix: "oban"]

  @doc """
  Registers a `setup_all` callback that swaps the mailer and PDF adapters for
  test doubles and restores the originals on exit.
  """
  @spec configure_test_adapters() :: :ok
  def configure_test_adapters do
    original_mailer_config = Application.get_env(:firmowid, Firmowid.Mailer)
    original_pdf_config = Application.get_env(:firmowid, Pdf)

    Application.put_env(:firmowid, Firmowid.Mailer, adapter: Firmowid.Test.Support.ResendTestAdapter)

    Application.put_env(:firmowid, Pdf, adapter: Firmowid.Test.Support.FakePdfAdapter)

    on_exit(fn ->
      Application.put_env(:firmowid, Firmowid.Mailer, original_mailer_config)
      Application.put_env(:firmowid, Pdf, original_pdf_config)
    end)

    :ok
  end

  @doc """
  Returns a base map of valid invoice attributes suitable for creating a
  sales invoice in tests.
  """
  @spec base_invoice_attrs() :: map()
  def base_invoice_attrs do
    %{
      invoice_type: :foreign,
      invoice_number: "FV/#{System.unique_integer([:positive])}",
      sale_date: Date.utc_today(),
      issue_date: Date.utc_today(),
      due_date: Date.add(Date.utc_today(), 14),
      payment_method: :transfer,
      currency: "EUR",
      seller_nip: "1234567890",
      seller_display_name: "Seller Sp. z o.o.",
      seller_address: "ul. Testowa 1, 00-001 Warszawa",
      seller_account_number: "DE99123456781234567812",
      buyer_type: :company,
      buyer_id: "DE123456789",
      buyer_full_name: "Buyer GmbH",
      buyer_display_name: "Buyer GmbH",
      buyer_address: "Teststrasse 1, 10115 Berlin",
      buyer_country: "DE",
      ksef_invoice_kind: :vat,
      sales_invoice_items: [base_item_attrs(%{})]
    }
  end

  @doc """
  Returns a base map of valid invoice line-item attributes, merged with the
  given `overrides`.
  """
  @spec base_item_attrs(map()) :: map()
  def base_item_attrs(overrides) do
    Enum.into(overrides, %{
      index: 0,
      name: "Programming service",
      quantity: Decimal.new("1"),
      unit: "szt.",
      unit_price: Decimal.new("100.00"),
      vat_rate: "23"
    })
  end

  @doc """
  Seeds a `Counterparty` with a unique, valid email address.
  """
  @spec valid_counterparty_fixture!(struct(), map()) :: struct()
  def valid_counterparty_fixture!(user, attrs \\ %{}) do
    alias Firmowid.Ash.Invoicing.Counterparty

    base_attrs = %{
      type: :company,
      tax_id: "DE123456789",
      full_name: "Counterparty GmbH",
      display_name: "Counterparty GmbH",
      address: "Counterpartystrasse 1, 10115 Berlin",
      country: "DE",
      email: "billing-#{System.unique_integer([:positive])}@example.com",
      organization_id: user.organization_id
    }

    Ash.Seed.seed!(Counterparty, Map.merge(base_attrs, attrs))
  end

  @doc """
  Performs the sales invoice email Oban job for `invoice` and `delivery_type`.
  """
  @spec perform_sales_invoice_email_job(struct(), atom(), keyword()) :: term()
  def perform_sales_invoice_email_job(invoice, delivery_type, opts \\ []) do
    opts = Keyword.merge(@oban_test_opts, opts)

    Oban.Testing.perform_job(
      SalesInvoiceEmailWorker,
      email_job_args(invoice, delivery_type),
      opts
    )
  end

  @doc """
  Asserts that a sales invoice email job is enqueued for `invoice` and `delivery_type`.
  """
  @spec assert_enqueued_email_job(struct(), atom()) :: true
  def assert_enqueued_email_job(invoice, delivery_type) do
    @oban_test_opts
    |> Keyword.merge(
      worker: SalesInvoiceEmailWorker,
      args: email_job_args(invoice, delivery_type)
    )
    |> Oban.Testing.assert_enqueued()
  end

  @doc """
  Refutes that a sales invoice email job is enqueued for `invoice` and `delivery_type`.
  """
  @spec refute_enqueued_email_job(struct(), atom()) :: false
  def refute_enqueued_email_job(invoice, delivery_type) do
    @oban_test_opts
    |> Keyword.merge(
      worker: SalesInvoiceEmailWorker,
      args: email_job_args(invoice, delivery_type)
    )
    |> Oban.Testing.refute_enqueued()
  end

  @doc """
  Returns delivery types persisted for `invoice`, ordered by insertion order.
  """
  @spec delivery_types_for(struct(), struct()) :: [atom()]
  def delivery_types_for(invoice, scope) do
    invoice
    |> email_deliveries_for(scope)
    |> Enum.map(& &1.delivery_type)
  end

  @doc """
  Returns email delivery records persisted for `invoice`, ordered by insertion order.
  """
  @spec email_deliveries_for(struct(), struct()) :: [struct()]
  def email_deliveries_for(invoice, scope) do
    SalesInvoiceEmailDelivery
    |> Ash.Query.filter(sales_invoice_id == ^invoice.id)
    |> Ash.Query.sort(inserted_at: :asc, id: :asc)
    |> Ash.read!(scope: scope)
  end

  @doc """
  Seeds an email delivery for `invoice`, merging common invoice fields with `attrs`.
  """
  @spec seed_email_delivery!(struct(), map()) :: struct()
  def seed_email_delivery!(invoice, attrs) do
    base_attrs = %{
      organization_id: invoice.organization_id,
      sales_invoice_id: invoice.id,
      recipient_email: "billing@example.com"
    }

    Ash.Seed.seed!(SalesInvoiceEmailDelivery, Map.merge(base_attrs, attrs))
  end

  @doc """
  Asserts that `delivery` represents a successfully sent email matching the
  given `expected` map with keys `:sales_invoice_id`, `:delivery_type`, and
  `:recipient_email`.
  """
  @spec assert_sent_delivery(struct(), map()) :: true
  def assert_sent_delivery(delivery, expected) do
    assert delivery.sales_invoice_id == expected.sales_invoice_id
    assert delivery.delivery_type == expected.delivery_type
    assert delivery.recipient_email == expected.recipient_email
    assert delivery.status == :sent
    assert %DateTime{} = delivery.sent_at
    assert is_nil(delivery.failed_at)
    assert is_binary(delivery.resend_email_id)
    assert delivery.resend_email_id != ""
    assert is_nil(delivery.error_message)
    true
  end

  defp email_job_args(invoice, delivery_type) do
    %{
      "organization_id" => invoice.organization_id,
      "sales_invoice_id" => invoice.id,
      "delivery_type" => Atom.to_string(delivery_type)
    }
  end
end
