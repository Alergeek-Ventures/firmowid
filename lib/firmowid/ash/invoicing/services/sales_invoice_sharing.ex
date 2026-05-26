defmodule Firmowid.Ash.Invoicing.Services.SalesInvoiceSharing do
  @moduledoc """
  Builds absolute public share URLs for sales invoices.

  Correction invoices share the root VAT invoice token, so every invoice in a
  correction chain resolves to the same public URL.
  """

  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Invoicing.Services.SalesInvoiceChain
  alias Firmowid.Ash.Scope
  alias FirmowidWeb.Core.Endpoint

  @doc """
  Generates or reuses the absolute public share URL for a sales invoice.
  """
  @spec get_share_url_for_sales_invoice(SalesInvoice.t(), Scope.t()) ::
          {:ok, String.t()}
  def get_share_url_for_sales_invoice(%SalesInvoice{ksef_invoice_kind: :kor} = sales_invoice, %Scope{} = scope) do
    root_invoice = SalesInvoiceChain.root_invoice(sales_invoice, scope: scope)

    case root_invoice.share_token do
      nil ->
        {:ok, root_invoice} = SalesInvoice.generate_share_token(root_invoice, scope: scope)

        {:ok, Endpoint.url() <> "/faktura/" <> root_invoice.share_token}

      root_token ->
        {:ok, Endpoint.url() <> "/faktura/" <> root_token}
    end
  end

  def get_share_url_for_sales_invoice(%SalesInvoice{share_token: nil} = sales_invoice, %Scope{} = scope) do
    {:ok, sales_invoice} = SalesInvoice.generate_share_token(sales_invoice, scope: scope)

    {:ok, Endpoint.url() <> "/faktura/" <> sales_invoice.share_token}
  end

  def get_share_url_for_sales_invoice(%SalesInvoice{share_token: token}, %Scope{}) do
    {:ok, Endpoint.url() <> "/faktura/" <> token}
  end
end
