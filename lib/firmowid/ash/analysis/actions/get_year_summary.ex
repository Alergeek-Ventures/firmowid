defmodule Firmowid.Ash.Analysis.Actions.GetYearSummary do
  @moduledoc "Returns annual analysis only for the authenticated member's organization."
  use Ash.Resource.Actions.Implementation

  alias Firmowid.Ash.Analysis
  alias Firmowid.Ash.Core.User
  alias Firmowid.Ash.Scope

  @impl true
  def run(input, _opts, %{actor: %User{member: %{organization_id: tenant, archived_at: nil}} = actor, tenant: tenant})
      when is_binary(tenant) do
    {:ok,
     Analysis.get_organization_yearly_totals(
       input.arguments.year,
       [tag_filters: input.arguments.tag_filters],
       Scope.new!(actor, tenant)
     )}
  end

  # Admin policy bypasses in downstream resources must not allow cross-tenant reads.
  def run(_input, _opts, _context), do: {:error, Ash.Error.Forbidden.exception([])}
end
