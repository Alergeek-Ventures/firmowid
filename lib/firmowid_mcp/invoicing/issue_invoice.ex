defmodule FirmowidMcp.Invoicing.IssueInvoice do
  @moduledoc "Read-only invoice preparation with issuance available only after widget confirmation."

  @doc "Returns the native preview tool that opens the confirmation widget."
  @spec tool_name() :: String.t()
  def tool_name, do: "preview_sales_invoice"

  @doc "Returns the native read-only tool used to validate invoice input."
  @spec data_tool_name() :: String.t()
  def data_tool_name, do: tool_name()

  @doc "Returns the stable resource identifier; the runtime adds a content hash."
  @spec resource_uri() :: String.t()
  def resource_uri, do: "ui://firmowid/invoicing/issue-invoice.html"

  @doc "Explains the confirmation workflow to the host."
  @spec widget_description() :: String.t()
  def widget_description do
    "Invoice preview and number selection. Only the user's confirmation in this widget issues " <>
      "the invoice and starts KSeF submission. Opening the widget saves nothing. It also handles " <>
      "previously saved drafts without a separate workflow and reports asynchronous KSeF progress. " <>
      "Do not claim issuance or KSeF acceptance before the widget reports it."
  end

  @doc "Returns the feature-owned confirmation LiveView."
  @spec live_view() :: module()
  def live_view, do: FirmowidMcp.Invoicing.Views.Issue

  @doc "Describes the read-only preparation tool, not the later user interaction."
  @spec annotations() :: map()
  def annotations, do: %{"readOnlyHint" => true, "destructiveHint" => false, "openWorldHint" => false}
end
