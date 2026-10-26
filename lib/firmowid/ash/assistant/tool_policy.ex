defmodule Firmowid.Ash.Assistant.ToolPolicy do
  @moduledoc "Resolves current user access and requires explicit consent for financial writes."

  alias Firmowid.Ash.Checks.ActorRole
  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Core.User
  alias Firmowid.Ash.Scope

  @read_tools ~w(list_transactions list_sales_invoices list_cost_invoices
    suggest_transaction_invoices suggest_sales_invoice_transactions
    suggest_cost_invoice_transactions)a
  @write_tools ~w(restore_transaction_for_matching connect_sales_invoice_transactions
    connect_cost_invoice_transactions disconnect_sales_invoice_transactions
    disconnect_cost_invoice_transactions)a
  @salary_tools ~w(list_monthly_salaries suggest_transaction_salaries)a
  @read_names Enum.map(@read_tools ++ @salary_tools, &Atom.to_string/1)

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

  @doc "Returns the tool allowlist for the user's current organization role."
  @spec tools(Scope.t()) :: [atom()]
  def tools(scope) do
    role = ActorRole.role(scope.actor)

    @read_tools ++
      if(role in [:admin, :accountant], do: @write_tools, else: []) ++
      if(role == :admin, do: @salary_tools, else: [])
  end

  @doc "Rejects unavailable tools, allows reads, and asks for approval of every write."
  @spec approve(map(), [String.t()]) :: :ok | :ask | {:deny, String.t()}
  def approve(%{name: name}, available) do
    cond do
      name not in available -> {:deny, "This operation is not available."}
      name in @read_names -> :ok
      true -> :ask
    end
  end

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
