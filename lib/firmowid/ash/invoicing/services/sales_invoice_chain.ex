defmodule Firmowid.Ash.Invoicing.Services.SalesInvoiceChain do
  @moduledoc """
  Helpers for traversing sales invoice correction chains.

  Corrections are stored as sibling rows that all point to the original VAT
  invoice through `corrected_invoice_id`. This module exposes a single place
  for resolving the root, latest, and previous invoice in that chain.
  """

  alias Firmowid.Ash.Invoicing.Calculations.AnnotatedCorrections
  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Invoicing.Utilities.SafeTimestamp

  @spec root_invoice(SalesInvoice.t(), keyword()) :: SalesInvoice.t()
  def root_invoice(%SalesInvoice{ksef_invoice_kind: :kor, corrected_invoice: %SalesInvoice{} = root}, _opts) do
    root
  end

  def root_invoice(%SalesInvoice{ksef_invoice_kind: :kor, corrected_invoice_id: corrected_invoice_id}, opts)
      when is_binary(corrected_invoice_id) do
    SalesInvoice.by_id!(corrected_invoice_id, opts)
  end

  def root_invoice(%SalesInvoice{} = invoice, _opts), do: invoice

  @spec ordered_chain(SalesInvoice.t(), keyword()) :: [SalesInvoice.t()]
  def ordered_chain(%SalesInvoice{} = invoice, opts) do
    root =
      invoice
      |> root_invoice(opts)
      |> Ash.load!([:corrections], opts)

    [root | root.corrections]
  end

  @spec latest_invoice(SalesInvoice.t(), keyword()) :: SalesInvoice.t()
  def latest_invoice(%SalesInvoice{} = invoice, opts) do
    invoice
    |> ordered_chain(opts)
    |> List.last()
  end

  @spec previous_invoice(SalesInvoice.t(), keyword()) :: SalesInvoice.t() | nil
  def previous_invoice(%SalesInvoice{} = invoice, opts) do
    chain = ordered_chain(invoice, opts)
    current_id = invoice.id

    chain
    |> Enum.with_index()
    |> Enum.find_value(fn
      {%SalesInvoice{id: ^current_id}, 0} -> nil
      {%SalesInvoice{id: ^current_id}, index} -> Enum.at(chain, index - 1)
      _other -> nil
    end)
  end

  @doc """
  Fetches the publicly authorized root invoice chain for a root share token.
  """
  @spec fetch_public_shared_chain!(Ash.UUID.t(), String.t(), keyword()) :: [SalesInvoice.t()]
  def fetch_public_shared_chain!(root_invoice_id, root_share_token, opts) do
    %{root_invoice_id: root_invoice_id, root_share_token: root_share_token}
    |> SalesInvoice.query_to_public_shared_chain(opts)
    |> Ash.Query.load([
      :organization,
      :net_value,
      :vat_value,
      :gross_value,
      :buyer_display_name_label,
      sales_invoice_items: [:net_value, :vat_value, :gross_value]
    ])
    |> Ash.read!(opts)
    |> assemble_public_shared_chain()
  end

  defp assemble_public_shared_chain(invoices) do
    root = Enum.find(invoices, &is_nil(&1.corrected_invoice_id))

    corrections =
      invoices
      |> Enum.reject(&is_nil(&1.corrected_invoice_id))
      |> Enum.sort_by(&SafeTimestamp.safe_timestamp/1, DateTime)

    root = %{root | corrections: corrections, reference_invoice: nil}

    annotated_corrections =
      root
      |> AnnotatedCorrections.annotate()
      |> Enum.map(&%{&1 | corrections: []})

    root = %{root | corrections: annotated_corrections}

    [root | annotated_corrections]
  end
end
