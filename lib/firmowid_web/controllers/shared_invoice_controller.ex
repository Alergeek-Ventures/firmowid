defmodule FirmowidWeb.SharedInvoiceController do
  @moduledoc """
  Handles public, unauthenticated access to shared invoices via token-based URLs.

  This controller serves the shared invoice preview page and PDF download
  without requiring authentication. Organization context is set explicitly
  via `Repo.put_org_id/1` since no auth plug provides it.
  """
  use FirmowidWeb, :controller

  alias Firmowid.Repo
  alias Firmowid.SalesInvoices
  alias Firmowid.SalesInvoices.Pdf

  require Logger

  # These pages render their own full HTML document via shared_page/1,
  # so we skip the application root layout to avoid nested <html> tags.
  plug :put_root_layout, html: false

  def show(conn, %{"token" => token_string} = params) do
    case SalesInvoices.get_invoice_by_share_token(token_string) do
      {:ok, invoice} ->
        {invoice, org} = prepare_invoice_with_org_context(invoice)
        lang = resolve_lang(params, invoice)

        render(conn, :show,
          layout: false,
          invoice: invoice,
          lang: lang,
          currency_rate: SalesInvoices.get_currency_rate(invoice),
          reference_invoice: SalesInvoices.get_reference_invoice(invoice),
          show_vat: org.is_vat_payer
        )

      {:error, :not_found} ->
        conn |> put_status(404) |> render(:not_found, layout: false)
    end
  end

  def pdf(conn, %{"token" => token_string}) do
    case SalesInvoices.get_invoice_by_share_token(token_string) do
      {:ok, invoice} ->
        {invoice, org} = prepare_invoice_with_org_context(invoice)

        case Pdf.generate(invoice, show_vat: org.is_vat_payer) do
          {:ok, pdf_binary} ->
            filename = (invoice.invoice_number || "faktura") <> ".pdf"

            conn
            |> put_resp_content_type("application/pdf")
            |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
            |> send_resp(200, pdf_binary)

          {:error, reason} ->
            Logger.error("PDF generation failed for shared invoice: #{inspect(reason)}")
            conn |> put_status(500) |> render(:error, layout: false)
        end

      {:error, :not_found} ->
        conn |> put_status(404) |> render(:not_found, layout: false)
    end
  end

  # Sets the organization context in the process dictionary (via Repo.put_org_id/1)
  # so that downstream queries (e.g. logo URL resolution) work on this
  # unauthenticated, public endpoint where no plug sets the org automatically.
  defp prepare_invoice_with_org_context(invoice) do
    org = invoice.organization
    Repo.put_org_id(invoice.organization_id)
    invoice = SalesInvoices.populate_logo_url(invoice)
    {invoice, org}
  end

  defp resolve_lang(%{"lang" => "pl"}, _invoice), do: :pl
  defp resolve_lang(%{"lang" => "en"}, _invoice), do: :en
  defp resolve_lang(_params, %{invoice_type: :foreign}), do: :en
  defp resolve_lang(_params, _invoice), do: :pl
end
