# credo:disable-for-this-file ExDNA.Credo
# Shared preview/PDF actions intentionally mirror token lookup and scoped rendering flow;
# reducing duplication requires a larger controller/service extraction.
defmodule FirmowidWeb.Invoicing.SalesInvoices.Controllers.Shared do
  @moduledoc """
  Handles public, unauthenticated access to shared invoices via token-based URLs.

  This controller serves the shared invoice preview page and PDF download
  without requiring authentication. After the initial cross-tenant lookup
  (justified Ecto exception — we don't know the org until we find the invoice),
  subsequent calls use an `:anonymous` SystemActor scoped to the invoice's org.
  """
  use FirmowidWeb, :controller

  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Invoicing.Services.SalesInvoicePdf
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor
  alias FirmowidWeb.Invoicing.Utilities.QueryCodec

  require Logger

  plug :put_view, html: FirmowidWeb.Invoicing.SalesInvoices.Components.SharedPage

  # These pages render their own full HTML document via shared_page/1,
  # so we skip the application root layout to avoid nested <html> tags.
  plug :put_root_layout, html: false

  def show(conn, %{"token" => token_string} = params) do
    # we dont need correction_id - this view uses root token to show all invoices including related corrections
    # but we need to split it to keep the old link format root_token.correction_id working
    {root_token, _correction_id} = split_pdf_token(token_string)

    case shared_invoice(root_token) do
      {:ok, invoice} ->
        scope = build_anonymous_scope(invoice)
        {invoice, logo_url, org} = prepare_invoice_with_org_context(invoice, scope)
        lang = resolve_lang(params, invoice)

        render(conn, :show,
          layout: false,
          invoice: invoice,
          logo_url: logo_url,
          lang: lang,
          buyer_display_name: invoice.buyer_display_name_label || "",
          currency_rate: Invoicing.get_currency_rate(invoice),
          show_vat: org.is_vat_payer
        )

      :not_found ->
        conn |> put_status(404) |> render(:not_found, layout: false)
    end
  end

  # pdf download needs to know the correction_id unlike the view
  def pdf(conn, %{"token" => token_string}) do
    {root_token, correction_id} = split_pdf_token(token_string)

    with {:ok, invoice} <- shared_invoice(root_token),
         scope = build_anonymous_scope(invoice),
         {invoice, logo_url, org} = prepare_invoice_with_org_context(invoice, scope),
         {:ok, target_invoice} <- target_pdf_invoice(invoice, correction_id),
         {:ok, pdf_binary} <-
           SalesInvoicePdf.generate(target_invoice,
             show_vat: org.is_vat_payer,
             logo_url: logo_url,
             include_internal_note: false,
             scope: scope
           ) do
      filename = (target_invoice.invoice_number || "faktura") <> ".pdf"

      conn
      |> put_resp_content_type("application/pdf")
      |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
      |> send_resp(200, pdf_binary)
    else
      :not_found -> conn |> put_status(404) |> render(:not_found, layout: false)
      {:error, _reason} -> conn |> put_status(500) |> render(:error, layout: false)
    end
  end

  defp shared_invoice(root_token) do
    case SalesInvoice.by_share_token(root_token, scope: anonymous_lookup_scope()) do
      {:ok, nil} -> :not_found
      {:ok, invoice} -> {:ok, invoice}
      {:error, _reason} -> :not_found
    end
  end

  defp split_pdf_token(token) do
    case String.split(token, ".", parts: 2) do
      [root, id] -> {root, id}
      [root] -> {root, nil}
    end
  end

  defp target_pdf_invoice(invoice, nil), do: {:ok, invoice}

  defp target_pdf_invoice(invoice, correction_id) do
    case Enum.find(invoice.corrections, &(&1.id == correction_id)) do
      nil -> :not_found
      correction -> {:ok, correction}
    end
  end

  defp build_anonymous_scope(invoice) do
    org_id = invoice.organization_id

    %Scope{
      actor: %SystemActor{org_id: org_id, role: :anonymous},
      tenant: org_id
    }
  end

  defp anonymous_lookup_scope do
    %Scope{actor: %SystemActor{org_id: nil, role: :anonymous}, tenant: nil}
  end

  defp prepare_invoice_with_org_context(invoice, scope) do
    org = invoice.organization
    logo_url = Invoicing.get_logo_url(invoice.organization_id, scope: scope)

    {invoice, logo_url, org}
  end

  defp resolve_lang(%{"jezyk" => raw_language}, invoice),
    do: QueryCodec.parse_invoice_language(raw_language) || resolve_lang(%{}, invoice)

  defp resolve_lang(_params, %{invoice_type: :foreign}), do: :en
  defp resolve_lang(_params, _invoice), do: :pl
end
