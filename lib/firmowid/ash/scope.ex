defmodule Firmowid.Ash.Scope do
  @moduledoc """
  Bundles actor and tenant into a single struct for Ash operations.

  Used as `scope:` option on all Ash calls.

  Fields:
  - `actor` — the acting entity (a `User`, `SystemActor`, or `nil`)
  - `tenant` — the organization ID (binary UUID or `nil`)
  """
  alias Firmowid.Ash.Scope

  defstruct [:actor, :tenant]

  @type t :: %__MODULE__{
          actor: map() | nil,
          tenant: binary() | nil
        }

  @doc """
  Builds a scope only when its tenant is owned by the actor.

  Human actors must use their `organization_id`; system actors are bound to
  their `org_id`. This constructor is the required boundary for request code.
  """
  @spec new(map(), binary() | nil) :: {:ok, t()} | {:error, :actor_tenant_mismatch}
  def new(%{organization_id: tenant} = actor, tenant), do: {:ok, %__MODULE__{actor: actor, tenant: tenant}}

  def new(%{org_id: tenant} = actor, tenant), do: {:ok, %__MODULE__{actor: actor, tenant: tenant}}
  def new(_actor, _tenant), do: {:error, :actor_tenant_mismatch}

  @doc "Builds a validated scope or raises when actor and tenant do not match."
  @spec new!(map(), binary() | nil) :: t()
  def new!(actor, tenant) do
    case new(actor, tenant) do
      {:ok, scope} -> scope
      {:error, :actor_tenant_mismatch} -> raise ArgumentError, "actor does not belong to tenant"
    end
  end

  defimpl Ash.Scope.ToOpts do
    @spec get_actor(Scope.t()) :: {:ok, term()} | :error
    def get_actor(%{actor: actor}), do: {:ok, actor}

    @spec get_tenant(Scope.t()) :: {:ok, term()} | :error
    def get_tenant(%{tenant: tenant}), do: {:ok, tenant}

    @spec get_context(Scope.t()) :: :error
    def get_context(_), do: :error

    @spec get_tracer(Scope.t()) :: :error
    def get_tracer(_), do: :error

    @spec get_authorize?(Scope.t()) :: :error
    def get_authorize?(_), do: :error
  end
end
