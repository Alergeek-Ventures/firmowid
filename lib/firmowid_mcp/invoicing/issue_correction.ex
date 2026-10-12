defmodule FirmowidMcp.Invoicing.IssueCorrection do
  @moduledoc "Read-only correction preparation with explicit user confirmation before issuance."

  @doc "Returns the correction preview tool that opens the confirmation widget."
  @spec tool_name() :: String.t()
  def tool_name, do: "preview_sales_invoice_correction"

  @doc "Returns the native read-only tool used to validate correction input."
  @spec data_tool_name() :: String.t()
  def data_tool_name, do: tool_name()

  @doc "Returns the stable resource identifier; the runtime adds a content hash."
  @spec resource_uri() :: String.t()
  def resource_uri, do: "ui://firmowid/invoicing/issue-correction.html"

  @doc "Explains the correction confirmation workflow to the host."
  @spec widget_description() :: String.t()
  def widget_description do
    "Correction preview showing the previous and corrected invoice values, with number selection " <>
      "and mandatory user confirmation. Opening this widget creates nothing. Confirmation issues " <>
      "the correction and starts KSeF submission; the widget reports progress and failure, including " <>
      "cleanup of an unsuccessful correction. Do not claim KSeF acceptance until confirmed."
  end

  @doc "Returns the shared feature-owned confirmation LiveView."
  @spec live_view() :: module()
  def live_view, do: FirmowidMcp.Invoicing.Views.Issue

  @doc "Describes the read-only preparation tool, not the later user interaction."
  @spec annotations() :: map()
  def annotations, do: %{"readOnlyHint" => true, "destructiveHint" => false, "openWorldHint" => false}
end
