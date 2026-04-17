defmodule Firmowid.Ash.Invoicing.Services.SalesInvoiceBasePdf do
  @moduledoc """
  Generates the base PDF for sales invoices without any post-processing.
  """

  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Invoicing.Services.PdfUtils
  alias FirmowidWeb.Infrastructure.Utilities.PdfHelpers

  @item_calcs [:net_value, :vat_value, :gross_value]
  @footer_logo_path Path.join(
                      :code.priv_dir(:firmowid),
                      "static/images/invoice_firmowid_logo.png"
                    )

  @doc """
  Generates the base sales-invoice PDF.
  """
  @spec generate(SalesInvoice.t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def generate(%SalesInvoice{} = invoice, opts \\ []) do
    alias Firmowid.Ash.Invoicing.Calculations.AnnotatedCorrections

    show_vat = Keyword.get(opts, :show_vat, true)
    ash_scope = Keyword.get(opts, :scope)
    ash_opts = ash_opts(invoice, ash_scope)
    logo_url = Keyword.get(opts, :logo_url, Map.get(invoice, :logo_url))

    logo_data_uri = PdfHelpers.url_to_data_uri(logo_url)
    footer_logo_data_uri = PdfHelpers.file_to_data_uri(@footer_logo_path)

    invoice =
      invoice
      |> Ash.load!(
        [
          :net_value,
          :vat_value,
          :gross_value,
          :internal_note,
          sales_invoice_items: @item_calcs,
          corrections: [sales_invoice_items: @item_calcs]
        ],
        ash_opts
      )
      |> maybe_load_reference_invoice(ash_opts)
      |> then(fn inv -> %{inv | corrections: AnnotatedCorrections.annotate(inv)} end)

    html_content =
      PdfHelpers.render_pdf_html(
        FirmowidWeb.Invoicing.SalesInvoices.Components.Pdf,
        :sales_invoice,
        layout: false,
        sales_invoice: invoice,
        currency_rate: Invoicing.get_currency_rate(invoice),
        reference_invoice: invoice.reference_invoice,
        show_vat: show_vat,
        logo_data_uri: logo_data_uri,
        footer_logo_data_uri: footer_logo_data_uri,
        class: "mx-auto",
        include_internal_note_page: false
      )

    PdfUtils.render_html_to_pdf(html_content, scale: 1.25)
  end

  defp maybe_load_reference_invoice(%{ksef_invoice_kind: kind} = invoice, _ash_opts) when kind != :kor, do: invoice

  defp maybe_load_reference_invoice(invoice, ash_opts) do
    invoice = Ash.load!(invoice, [:reference_invoice, :corrected_invoice], ash_opts)

    reference_invoice =
      Ash.load!(
        invoice.reference_invoice,
        [:net_value, :vat_value, :gross_value, sales_invoice_items: @item_calcs],
        ash_opts
      )

    %{invoice | reference_invoice: reference_invoice}
  end

  defp ash_opts(invoice, nil), do: [tenant: invoice.organization_id]
  defp ash_opts(_invoice, scope), do: [scope: scope]
end
