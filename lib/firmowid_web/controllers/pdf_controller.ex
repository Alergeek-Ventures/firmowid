defmodule FirmowidWeb.PdfController do
  alias Firmowid.Nbp
  alias Firmowid.Invoices
  use FirmowidWeb, :controller

  def index(conn, %{"id" => id}) do
    invoice =
      Invoices.get_invoice(id)

    conn |> render_invoice(invoice)
  end

  defp render_invoice(conn, %Invoices.Invoice{} = invoice) do
    currency_rate =
      case invoice.currency do
        "PLN" ->
          nil

        currency ->
          Nbp.ApiClient.get_exchange_rate(
            currency,
            Invoices.Invoice.get_currency_conversion_date(invoice)
          )
      end

    conn
    |> render(:invoice,
      layout: false,
      invoice: invoice,
      currency_rate: currency_rate
    )
  end

  defp render_invoice(conn, nil) do
    conn |> send_resp(404, "Not found")
  end

  def pdf(conn, %{"id" => id}) do
    evaluate = %{
      expression: """
      document.querySelector('body').classList.add('bg-white');
      """
    }

    case Invoices.get_invoice(id) do
      nil ->
        conn
        |> send_resp(404, "Not found")

      invoice ->
        url_with_protocol = FirmowidWeb.Endpoint.url()
        domain = FirmowidWeb.Endpoint.host()

        {:ok, result} =
          ChromicPDF.print_to_pdf(
            {:url, "#{url_with_protocol}/invoices/#{id}/pdf"},
            set_cookie: %{
              name: "_firmowid_key",
              value: conn.cookies["_firmowid_key"],
              domain: domain
            },
            output: fn path ->
              conn
              |> put_resp_header(
                "content-disposition",
                "attachment; filename=#{invoice.invoice_number}.pdf"
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
