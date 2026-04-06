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
