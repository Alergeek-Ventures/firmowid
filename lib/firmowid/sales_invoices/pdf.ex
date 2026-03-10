defmodule Firmowid.SalesInvoices.Pdf do
  @moduledoc """
  Generates PDF binaries for sales invoices using ChromicPDF.
  """

  alias Firmowid.SalesInvoices
  alias Firmowid.SalesInvoices.SalesInvoice
  alias FirmowidWeb.PdfHelpers

  @dialyzer {:nowarn_function, generate: 1, generate: 2}
  @spec generate(SalesInvoice.t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def generate(%SalesInvoice{} = invoice, opts \\ []) do
    show_vat = Keyword.get(opts, :show_vat, true)

    logo_data_uri = PdfHelpers.url_to_data_uri(invoice.logo_url)

    footer_logo_path =
      Path.join(:code.priv_dir(:firmowid), "static/images/invoice_firmowid_logo.png")

    footer_logo_data_uri = PdfHelpers.file_to_data_uri(footer_logo_path)

    invoice = SalesInvoices.populate_reference_invoices(invoice)

    html_content =
      PdfHelpers.render_pdf_html(
        FirmowidWeb.PdfHTML,
        :sales_invoice,
        layout: false,
        sales_invoice: invoice,
        currency_rate: SalesInvoices.get_currency_rate(invoice),
        reference_invoice: invoice.reference_invoice,
        show_vat: show_vat,
        logo_data_uri: logo_data_uri,
        footer_logo_data_uri: footer_logo_data_uri,
        class: "mx-auto"
      )

    evaluate = %{
      expression: """
      document.querySelector('body').classList.add('bg-white');
      """
    }

    ChromicPDF.print_to_pdf(
      {:html, html_content},
      output: fn path -> File.read!(path) end,
      page_size: "A4",
      evaluate: evaluate,
      print_to_pdf: %{
        marginTop: 0,
        marginLeft: 0,
        marginRight: 0,
        marginBottom: 0,
        scale: 1.25,
        printBackground: true
      }
    )
  end
end
