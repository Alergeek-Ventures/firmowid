defmodule Firmowid.Core.Changes.RequireGrantTenant do
  @moduledoc """
  Limits exchanging an OAuth grant to a request in the grant's organization.

  The tenant is minted into the new access token, so an organization-bound code or
  refresh token exchanged without it (or under another one) would yield a token
  for the default organization instead. A request without a tenant only matches
  grants without an organization, issued before it was chosen on the consent
  screen.
  """

  use Ash.Resource.Change

  alias Ash.Resource.Change.Context

  require Ash.Expr

  @doc false
  @impl true
  @spec change(Ash.Changeset.t(), keyword(), Context.t()) :: Ash.Changeset.t()
  def change(%{tenant: nil} = changeset, _opts, _context),
    do: Ash.Changeset.filter(changeset, Ash.Expr.expr(is_nil(organization_id)))

  def change(%{tenant: tenant} = changeset, _opts, _context),
    do: Ash.Changeset.filter(changeset, Ash.Expr.expr(organization_id == ^tenant))

  @doc false
  @impl true
  @spec atomic(Ash.Changeset.t(), keyword(), Context.t()) ::
          {:ok, Ash.Changeset.t()}
  def atomic(changeset, opts, context), do: {:ok, change(changeset, opts, context)}
end
