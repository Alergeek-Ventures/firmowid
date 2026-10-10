defmodule FirmowidWeb.Invoicing.Mcp do
  @moduledoc "The feature-owned, authenticated MCP invoice list UI resource."

  use Ash.Domain, extensions: [AshAi]

  alias FirmowidWeb.Invoicing.Mcp.Document

  mcp_resources do
    mcp_resource :invoices, "ui://firmowid/invoicing/invoices-v1.html", Document, :read,
      title: "Invoices",
      description: "Read-only sales and cost invoice list for the authenticated company.",
      mime_type: "text/html;profile=mcp-app"
  end

  resources do
    resource Document
  end
end
