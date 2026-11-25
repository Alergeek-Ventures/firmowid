defmodule Firmowid.Invoicing.SalesInvoice.OrganizationTenantList do
  @moduledoc """
  Lists organization IDs for the AshOban scheduled actions that run per tenant: sales invoice
  reminders and the tax forecast of `Firmowid.Taxes.TaxYear`.
  """

  @behaviour AshOban.ListTenants

  alias Firmowid.Core.Organization
  alias Firmowid.Scope
  alias Firmowid.SystemActor

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
