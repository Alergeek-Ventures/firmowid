defmodule Firmowid.Checks.ApiKeyScope do
  @moduledoc """
  Policy check that returns true when the actor signed in with an API key that has the
  given scope (see `Firmowid.Core.ApiKey`). An actor without a key never matches.

  ## Options

  - `scope` — the required scope (required)

  ## Usage

      policy AshAuthentication.Checks.UsingApiKey do
        forbid_unless {ApiKeyScope, scope: :sales_invoices}
        authorize_if action(:issue)
      end
  """
  use Ash.Policy.SimpleCheck

  @impl true
  def describe(opts), do: "actor uses an API key with the #{inspect(Keyword.get(opts, :scope))} scope"

  @impl true
  def match?(%{__metadata__: %{api_key: %{scopes: scopes}}}, _context, opts) when is_list(scopes),
    do: {:ok, Keyword.fetch!(opts, :scope) in scopes}

  def match?(_actor, _context, _opts), do: {:ok, false}
end
