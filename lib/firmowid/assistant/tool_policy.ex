defmodule Firmowid.Assistant.ToolPolicy do
  @moduledoc "Resolves current user access and requires explicit consent for financial writes."

  alias Firmowid.Checks.ActorRole
  alias Firmowid.Core
  alias Firmowid.Core.User
  alias Firmowid.Invoicing
  alias Firmowid.Invoicing.FailureReporter
  alias Firmowid.Scope

  @read_tools ~w(list_transactions list_sales_invoices list_cost_invoices list_counterparties
    get_ksef_connection_status suggest_transaction_invoices suggest_sales_invoice_transactions
    suggest_cost_invoice_transactions)a
  # The numbering lookup is read-only, but SalesInvoice authorizes its generic actions for issuers only.
  @issuer_read_tools ~w(get_next_sales_invoice_number)a
  @write_tools ~w(restore_transaction_for_matching connect_sales_invoice_transactions
    connect_cost_invoice_transactions disconnect_sales_invoice_transactions
    disconnect_cost_invoice_transactions issue_sales_invoice link_sales_invoice_counterparty)a
  @salary_tools ~w(list_monthly_salaries suggest_transaction_salaries)a
  @read_names Enum.map(@read_tools ++ @issuer_read_tools ++ @salary_tools, &Atom.to_string/1)

  @doc "Reloads membership so revocation and role changes take effect before executing a run."
  @spec fresh_scope(map()) :: {:ok, Scope.t()} | {:error, :actor_tenant_mismatch}
  def fresh_scope(conversation) do
    identity = %User{id: conversation.user_id, member: nil}

    case Core.get_user(conversation.user_id, actor: identity, not_found_error?: false) do
      {:ok, nil} ->
        {:error, :actor_tenant_mismatch}

      {:ok, user} ->
        user
        |> Core.load_member(conversation.organization_id)
        |> Scope.new(conversation.organization_id)

      {:error, error} ->
        raise Ash.Error.to_error_class(error)
    end
  end

  @doc "Stops a tool call if the run's membership or authority has changed."
  @spec ensure_current!(Scope.t()) :: :ok
  def ensure_current!(scope) do
    identity = %{user_id: scope.actor.id, organization_id: scope.tenant}

    with {:ok, current} <- fresh_scope(identity),
         true <-
           current.actor.member.id == scope.actor.member.id and
             current.actor.member.role == scope.actor.member.role and
             current.actor.system_role == scope.actor.system_role do
      :ok
    else
      _ -> raise Ash.Error.Forbidden
    end
  end

  @doc "Returns the tool allowlist for the user's current organization role."
  @spec tools(Scope.t()) :: [atom()]
  def tools(scope) do
    role = ActorRole.role(scope.actor)

    @read_tools ++
      if(role in [:admin, :accountant], do: @issuer_read_tools ++ @write_tools, else: []) ++
      if(role == :admin, do: @salary_tools, else: [])
  end

  @doc """
  Rejects unavailable tools, allows reads, and asks for approval of every write. An invoice
  the issuing action would reject goes back to the model with its errors instead of to the user.
  """
  @spec approve(map(), [String.t()], Scope.t()) :: :ok | :ask | {:deny, String.t()}
  def approve(%{name: name} = call, available, scope) do
    cond do
      name not in available -> {:deny, "This operation is not available."}
      name in @read_names -> :ok
      name == "issue_sales_invoice" -> approve_issue(call.arguments, scope)
      true -> :ask
    end
  end

  defp approve_issue(%{"input" => %{"invoice" => invoice}}, scope) when is_map(invoice) do
    case Invoicing.preview_issued_sales_invoice(invoice, actor: scope.actor, tenant: scope.tenant) do
      {:ok, _invoice} ->
        :ask

      {:error, error} ->
        FailureReporter.report_unexpected(error, :issue, scope.tenant)

        {:deny,
         "Not shown to the user and nothing was issued: the invoice data is invalid. " <>
           "Correct it and call issue_sales_invoice again. Errors: " <>
           Enum.map_join(Ash.Error.to_error_class(error).errors, "; ", &Exception.message/1)}
    end
  end

  defp approve_issue(_arguments, _scope), do: {:deny, "Not shown to the user: pass the invoice fields in invoice."}

  @doc "Decodes only the explicit decisions bound to the persisted plan."
  @spec approvals(map()) :: map()
  def approvals(decisions) do
    Map.new(decisions, fn
      {id, "approve"} ->
        {id, :approve}

      {id, "deny"} ->
        {id, {:deny, "The user clicked Reject. Operation intentionally denied by the user, not an application failure."}}
    end)
  end
end
