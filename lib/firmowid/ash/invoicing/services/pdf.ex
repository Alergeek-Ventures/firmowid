defmodule Firmowid.Ash.Invoicing.Services.Pdf do
  @moduledoc """
  Generates PDF binaries for sales invoices using ChromicPDF.
  """

  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias FirmowidWeb.Infrastructure.Utilities.PdfHelpers

  # sobelow_skip ["Traversal.FileModule"]
  # Path in the output callback comes from ChromicPDF (framework-generated temp file),
  # not user input.
  @dialyzer {:nowarn_function, generate: 1, generate: 2}
  @spec generate(SalesInvoice.t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def generate(%SalesInvoice{} = invoice, opts \\ []) do
    alias Firmowid.Ash.Invoicing.Calculations.AnnotatedCorrections

    show_vat = Keyword.get(opts, :show_vat, true)

    logo_data_uri = PdfHelpers.url_to_data_uri(Map.get(invoice, :logo_url))

    footer_logo_path =
      Path.join(:code.priv_dir(:firmowid), "static/images/invoice_firmowid_logo.png")

    footer_logo_data_uri = PdfHelpers.file_to_data_uri(footer_logo_path)

    invoice =
      invoice
      |> Ash.load!([corrections: :sales_invoice_items],
        authorize?: false,
        actor: %{},
        tenant: invoice.organization_id
      )
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
