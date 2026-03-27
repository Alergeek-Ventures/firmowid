defmodule Firmowid.Ash.Scope do
  @moduledoc """
  Bundles actor and tenant into a single struct for Ash operations.

  Used as `scope:` option on all Ash calls. During migration, both this and
  `Repo.put_org_id/1` coexist — this for Ash domains, `put_org_id` for Ecto contexts.
  """
  alias Firmowid.Ash.Scope

  defstruct [:current_user, :current_tenant]

  @type t :: %__MODULE__{
          current_user: map() | nil,
          current_tenant: binary() | nil
        }

  defimpl Ash.Scope.ToOpts do
    @spec get_actor(Scope.t()) :: {:ok, term()} | :error
    def get_actor(%{current_user: user}), do: {:ok, user}

    @spec get_tenant(Scope.t()) :: {:ok, term()} | :error
    def get_tenant(%{current_tenant: tenant}), do: {:ok, tenant}

    @spec get_context(Scope.t()) :: :error
    def get_context(_), do: :error

    @spec get_tracer(Scope.t()) :: :error
    def get_tracer(_), do: :error

    @spec get_authorize?(Scope.t()) :: :error
    def get_authorize?(_), do: :error
  end
end
