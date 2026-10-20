defmodule FirmowidMcp.Invoicing do
  @moduledoc "Model guidance for invoice reading, optional drafts and user-confirmed issuance."

  @doc "Restricts invoice preparation and issuance to business buyers on the MCP interface."
  @spec action_context() :: %{shared: %{business_buyers_only?: true}}
  def action_context, do: %{shared: %{business_buyers_only?: true}}

  @doc "Returns the invoice workflow instructions advertised by the MCP server."
  @spec instructions() :: String.t()
  def instructions do
    """
    Before working with invoices, call get_ksef_connection_status for the authenticated organization.
    If disconnected or expired, propose connecting KSeF using show_ksef_connection when can_connect is true;
    otherwise explain that an organization administrator must connect it.
    Stored invoice data remains available without a KSeF connection: continue reading it if the user wants,
    and explain that it may be out of date. A connected status does not guarantee synchronization freshness;
    the server does not currently track the time of the last successful synchronization.
    Use list_sales_invoices and list_cost_invoices to read invoice data with filters and pagination.
    Use get_sales_invoice to read an invoice's items, effective correction chain and KSeF submission status.

    Prepare, save, revise and issue invoices only for business buyers (sole traders and companies)
    with a tax ID. Consumer invoices are not supported by these workflows, including existing drafts
    and corrections. Existing invoices remain readable regardless of buyer type.
    For a private buyer, do not relabel them as a company or ask for a PESEL. Direct the user to
    the Firmowid web app: #{FirmowidMcp.endpoint().url()}#{FirmowidWeb.Invoicing.Utilities.Navigation.sales_invoice_creator_path()}.
    Collect invoice data in the conversation, then call preview_sales_invoice to open the confirmation widget.
    For corrections, first read the source invoice with get_sales_invoice, then call preview_sales_invoice_correction.
    The user must review the document, select its number and confirm issuance inside the widget.
    Never issue an invoice or correction just because the user approved it in chat. Opening a preview is read-only;
    only a widget click issues the document and starts submission. Issuance requires an active KSeF connection.
    Stop after a preview widget opens and let the user interact; do not repeat the invoice beneath it.
    The widget reports whether the document is sending, accepted by KSeF, returned to a draft or removed after a failed correction.
    A saved document or queued job is not KSeF acceptance. Never claim acceptance until a KSeF number is present.

    A saved draft is optional, not a required step. Prefer collecting data in chat and opening the preview directly.
    A draft is a complete invoice without a number, never partial data; incomplete details stay in the conversation.
    Use create_sales_invoice_draft only when the user explicitly wants to issue a complete invoice later, and
    update_sales_invoice_draft to revise such a draft; both are available without KSeF.
    To issue a draft, pass its invoice_id to preview_sales_invoice and follow the same confirmation widget.
    The draft keeps its ID when issued. If KSeF does not accept an issued invoice, it returns to a draft without a number;
    a rejected correction is removed.
    """
  end
end
