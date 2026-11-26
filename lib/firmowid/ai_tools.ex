defmodule Firmowid.AiTools do
  @moduledoc """
  Keeps the MCP server, the in-app assistant and the public API (`/api/v1`) on the same tools:
  all three read their AshAi tools from here, and each difference between them is listed with
  its reason. Ash policies authorize every call, so a policy also hides the tools of features
  the organization's plan does not include, and AshAi hides tools the actor's role can never
  use.
  """

  @shared [
    :list_sessions,
    :get_current_session,
    :stop_current_session,
    :start_session,
    :edit_session,
    :add_sessions,
    :list_leave_requests,
    :create_leave_request,
    :update_profile,
    :get_shared_birthday,
    :list_projects,
    :list_sales_invoices,
    :list_cost_invoices,
    :get_sales_invoice,
    :preview_sales_invoice,
    :preview_sales_invoice_correction,
    :get_next_sales_invoice_number,
    :create_sales_invoice_draft,
    :update_sales_invoice_draft,
    :update_sales_invoice_internal_note,
    :update_cost_invoice_internal_note,
    :suggest_sales_invoice_transactions,
    :suggest_cost_invoice_transactions,
    :list_counterparties,
    :link_sales_invoice_counterparty,
    :connect_sales_invoice_transactions,
    :connect_cost_invoice_transactions,
    :disconnect_sales_invoice_transactions,
    :disconnect_cost_invoice_transactions,
    :list_transactions,
    :update_transaction_internal_note,
    :suggest_transaction_invoices,
    :restore_transaction_for_matching,
    :list_expected_transactions,
    :connect_expected_transaction_transactions,
    :disconnect_expected_transaction_transactions,
    :list_monthly_salaries,
    :suggest_transaction_salaries,
    :connect_transaction_salary,
    :disconnect_transaction_salary,
    :get_ksef_connection_status,
    :list_analysis_entries,
    :list_analysis_tags,
    :set_analysis_entry_category,
    :set_analysis_entry_project_tags,
    :list_tax_years,
    :suggest_tax_settings,
    :forecast_taxes
  ]

  # The confirmation widget reports the KSeF outcome on MCP; the assistant's invoice card shows it
  # to the user, and the assistant reads it with wait_for_ksef_submissions when asked.
  @assistant_only [:wait_for_ksef_submissions]

  # Another system's order is issued over the API without anyone confirming it, so a store can
  # invoice its orders; MCP issues an invoice only after the user confirms it in its widget.
  @api_only [:issue_sales_invoice_from_api]

  @doc "Returns the tools exposed by the MCP server."
  @spec mcp() :: [atom()]
  def mcp, do: @shared

  @doc "Returns the tools exposed to the in-app assistant."
  @spec assistant() :: [atom()]
  def assistant, do: @shared ++ @assistant_only

  @doc "Returns the tools exposed by the public API, one endpoint each."
  @spec api() :: [atom()]
  def api, do: @shared ++ @api_only
end
