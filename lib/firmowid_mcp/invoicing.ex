defmodule FirmowidMcp.Invoicing do
  @moduledoc "Model guidance for reading invoice data through MCP."

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
    """
  end
end
