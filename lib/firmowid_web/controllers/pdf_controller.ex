defmodule FirmowidWeb.PdfController do
  use FirmowidWeb, :controller

  alias Firmowid.Nbp
  alias Firmowid.SalesInvoices
  alias FirmowidWeb.PdfHelpers

  def index(conn, %{"id" => id}) do
    sales_invoice =
      SalesInvoices.get_sales_invoice_with_logo_url(id)

    render_sales_invoice(conn, sales_invoice)
  end

  defp render_sales_invoice(conn, %SalesInvoices.SalesInvoice{} = sales_invoice) do
    currency_rate =
      case sales_invoice.currency do
        "PLN" ->
          nil

        currency ->
          Nbp.ApiClient.get_exchange_rate(
            currency,
            SalesInvoices.SalesInvoice.get_currency_conversion_date(sales_invoice)
          )
      end

    render(conn, :sales_invoice,
      layout: false,
      sales_invoice: sales_invoice,
      currency_rate: currency_rate,
      class: "mx-auto",
      show_vat: conn.assigns.current_org.is_vat_payer,
      logo_data_uri: nil,
      footer_logo_data_uri: nil
    )
  end

  defp render_sales_invoice(conn, nil) do
    send_resp(conn, 404, "Not found")
  end

  # sobelow_skip ["Traversal.SendFile"]
  # This is safe because path is not user-controlled
  def pdf(conn, %{"id" => id}) do
    case SalesInvoices.get_sales_invoice_with_logo_url(id) do
      nil ->
        send_resp(conn, 404, "Not found")

      sales_invoice ->
        # Convert logo URL to data URI for embedding
        logo_data_uri = PdfHelpers.url_to_data_uri(sales_invoice.logo_url)

        # Convert footer logo from static file to data URI
        footer_logo_path = Path.join(:code.priv_dir(:firmowid), "static/images/invoice_firmowid_logo.png")
        footer_logo_data_uri = PdfHelpers.file_to_data_uri(footer_logo_path)

        currency_rate =
          case sales_invoice.currency do
            "PLN" ->
              nil

            currency ->
              Nbp.ApiClient.get_exchange_rate(
                currency,
                SalesInvoices.SalesInvoice.get_currency_conversion_date(sales_invoice)
              )
          end

        # Render HTML to string
        html_content =
          PdfHelpers.render_pdf_html(
            FirmowidWeb.PdfHTML,
            :sales_invoice,
            layout: false,
            sales_invoice: sales_invoice,
            currency_rate: currency_rate,
            show_vat: conn.assigns.current_org.is_vat_payer,
            logo_data_uri: logo_data_uri,
            footer_logo_data_uri: footer_logo_data_uri,
            class: "mx-auto"
          )

        # Add script to ensure white background
        evaluate = %{
          expression: """
          document.querySelector('body').classList.add('bg-white');
          """
        }

        {:ok, result} =
          ChromicPDF.print_to_pdf(
            {:html, html_content},
            output: fn path ->
              conn
              |> put_resp_header(
                "content-disposition",
                "attachment; filename=#{sales_invoice.invoice_number}.pdf"
              )
              |> send_file(200, path)
            end,
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

        result
    end
  end
end
