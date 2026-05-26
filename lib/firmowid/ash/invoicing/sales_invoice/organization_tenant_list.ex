defmodule Firmowid.Ash.Invoicing.SalesInvoice.OrganizationTenantList do
  @moduledoc """
  Lists organization IDs for sales invoice AshOban scheduled actions that run per tenant.
  """

  @behaviour AshOban.ListTenants

  alias Firmowid.Ash.Core.Organization
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor

  @doc false
  @impl true
  @spec list_tenants(Keyword.t()) :: [String.t()]
  def list_tenants(_opts) do
    Organization
    |> Ash.Query.select([:id])
    |> Ash.read!(scope: %Scope{actor: %SystemActor{org_id: nil, role: :cross_tenant_reader}, tenant: nil})
    |> Enum.map(& &1.id)
  end
end
