defmodule Firmowid.AiTools do
  @moduledoc """
  Keeps the MCP server and the in-app assistant on the same access: both read their AshAi
  tools from here, and each difference between them is listed with its reason. Ash policies
  authorize every call, and AshAi hides tools the actor's role can never use.
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
    :list_monthly_salaries,
    :suggest_transaction_salaries,
    :connect_transaction_salary,
    :disconnect_transaction_salary,
    :get_ksef_connection_status,
    :list_analysis_entries,
    :list_analysis_tags,
    :set_analysis_entry_category,
    :set_analysis_entry_project_tags
  ]

  # Opens the KSeF connection MCP app. The assistant cannot render MCP apps and reads the same
  # status through get_ksef_connection_status.
  @mcp_only [:show_ksef_connection]

  # issue_sales_invoice issues as soon as the call runs. The assistant runs it only after the
  # user approves its preview on the approval card; MCP has no such card and issues only from
  # the confirmation widget that preview_sales_invoice opens. That widget also reports the KSeF
  # outcome, which the assistant waits for with wait_for_ksef_submissions instead.
  @assistant_only [:issue_sales_invoice, :wait_for_ksef_submissions]

  # Writes the assistant's approval card cannot show yet: the user could not see what changes,
  # so the assistant gets them once each has its card. The assistant prompt names them as
  # changes it does not make; update it together with this list.
  @awaiting_approval_card [
    :start_session,
    :stop_current_session,
    :edit_session,
    :add_sessions,
    :create_leave_request,
    :update_profile,
    :create_sales_invoice_draft,
    :update_sales_invoice_draft,
    :update_sales_invoice_internal_note,
    :update_cost_invoice_internal_note,
    :update_transaction_internal_note,
    :connect_transaction_salary,
    :disconnect_transaction_salary,
    :set_analysis_entry_category,
    :set_analysis_entry_project_tags
  ]

  @doc "Returns the tools exposed by the MCP server."
  @spec mcp() :: [atom()]
  def mcp, do: @shared ++ @mcp_only

  @doc "Returns the tools exposed to the in-app assistant."
  @spec assistant() :: [atom()]
  def assistant, do: (@shared -- @awaiting_approval_card) ++ @assistant_only
end
