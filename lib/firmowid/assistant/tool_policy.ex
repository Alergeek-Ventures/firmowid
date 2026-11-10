defmodule Firmowid.Assistant.ToolPolicy do
  @moduledoc "Resolves current user access and requires explicit consent for every write."

  alias Firmowid.AiTools
  alias Firmowid.Core
  alias Firmowid.Core.User
  alias Firmowid.Scope

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

  @doc """
  Returns the assistant's tools the actor may use. AshAi drops tools whose policies forbid every
  call for the actor's role, the same way it does for MCP; Ash policies authorize each call.
  """
  @spec tools(Scope.t()) :: [%AshAi.Tool{}]
  def tools(scope) do
    AshAi.exposed_tools(
      otp_app: :firmowid,
      tools: AiTools.assistant(),
      actor: scope.actor,
      tenant: scope.tenant
    )
  end

  @doc """
  Rejects unavailable tools, runs tools annotated read-only, and asks for approval of every other
  call. Invoices are issued from the confirmation widget the preview tools open, not by a call.
  """
  @spec approve(map(), [%AshAi.Tool{}]) :: :ok | :ask | {:deny, String.t()}
  def approve(%{name: name}, tools) do
    case Enum.find(tools, &(Atom.to_string(&1.name) == name)) do
      nil -> {:deny, "This operation is not available."}
      tool -> if Keyword.get(tool.annotations, :read_only_hint) == true, do: :ok, else: :ask
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
