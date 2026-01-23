defmodule Firmowid.Billing do
  @moduledoc """
  Context for managing organization billing limits.

  Provides soft limits for cost invoices, sales invoices, and bank connections.
  Limits are checked but not enforced - actions proceed with warnings when over limit.

  Monthly invoice counters are reset by `Firmowid.Billing.ResetWorker` on the 1st of each month.
  """

  import Ecto.Query, warn: false

  alias Firmowid.Billing.Limits
  alias Firmowid.Repo

  @type limit_type :: :cost_invoices | :sales_invoices | :bank_connections
  @type check_result :: :ok | {:warning, :over_limit, %{used: integer(), limit: integer()}}

  @doc """
  Checks if the organization is within limits for the given resource type.

  Returns `:ok` if within limits, or `{:warning, :over_limit, %{used: x, limit: y}}`
  if over the limit. This is a soft limit - actions should still proceed.
  """
  @spec check(binary(), limit_type()) :: check_result()
  def check(organization_id, type) when type in [:cost_invoices, :sales_invoices, :bank_connections] do
    limits = get_limits!(organization_id)
    {used, limit} = get_usage_and_limit(limits, type)

    if used >= limit do
      {:warning, :over_limit, %{used: used, limit: limit}}
    else
      :ok
    end
  end

  @doc """
  Increments the usage counter for the given resource type.
  """
  @spec increment(binary(), limit_type()) :: {:ok, Limits.t()} | {:error, Ecto.Changeset.t()}
  def increment(organization_id, type) when type in [:cost_invoices, :sales_invoices, :bank_connections] do
    limits = get_limits!(organization_id)
    field = usage_field(type)
    current_value = Map.get(limits, field)

    limits
    |> Limits.changeset(%{field => current_value + 1})
    |> Repo.update(skip_organization_id: true)
  end

  @doc """
  Decrements the usage counter for the given resource type. Will not go below zero.
  """
  @spec decrement(binary(), limit_type()) :: {:ok, Limits.t()} | {:error, Ecto.Changeset.t()}
  def decrement(organization_id, type) when type in [:cost_invoices, :sales_invoices, :bank_connections] do
    limits = get_limits!(organization_id)
    field = usage_field(type)
    current_value = Map.get(limits, field)
    new_value = max(0, current_value - 1)

    limits
    |> Limits.changeset(%{field => new_value})
    |> Repo.update(skip_organization_id: true)
  end

  @doc """
  Gets the limits for an organization. Raises if not found.
  """
  @spec get_limits!(binary()) :: Limits.t()
  def get_limits!(organization_id) do
    Limits
    |> where([l], l.organization_id == ^organization_id)
    |> Repo.one!(skip_organization_id: true)
  end

  @doc """
  Creates a new limits record for an organization with default values.
  """
  @spec create_limits(binary()) :: Limits.t()
  def create_limits(organization_id) do
    %Limits{}
    |> Limits.changeset(%{organization_id: organization_id})
    |> Repo.insert!(skip_organization_id: true)
  end

  @doc """
  Gets usage summary for an organization.
  """
  @spec get_usage_summary(binary()) :: %{
          cost_invoices: %{used: integer(), limit: integer(), over_limit: boolean()},
          sales_invoices: %{used: integer(), limit: integer(), over_limit: boolean()},
          bank_connections: %{used: integer(), limit: integer(), over_limit: boolean()}
        }
  def get_usage_summary(organization_id) do
    limits = get_limits!(organization_id)

    %{
      cost_invoices: build_usage_map(limits, :cost_invoices),
      sales_invoices: build_usage_map(limits, :sales_invoices),
      bank_connections: build_usage_map(limits, :bank_connections)
    }
  end

  @doc """
  Resets monthly invoice counters for all organizations.
  Called by `Firmowid.Billing.ResetWorker` on the 1st of each month.
  """
  @spec reset_monthly_counters() :: {integer(), nil}
  def reset_monthly_counters do
    Repo.update_all(
      Limits,
      [set: [cost_invoices_used: 0, sales_invoices_used: 0, updated_at: DateTime.utc_now()]],
      skip_organization_id: true
    )
  end

  defp get_usage_and_limit(limits, :cost_invoices) do
    {limits.cost_invoices_used, limits.cost_invoices_limit}
  end

  defp get_usage_and_limit(limits, :sales_invoices) do
    {limits.sales_invoices_used, limits.sales_invoices_limit}
  end

  defp get_usage_and_limit(limits, :bank_connections) do
    {limits.bank_connections_used, limits.bank_connections_limit}
  end

  defp usage_field(:cost_invoices), do: :cost_invoices_used
  defp usage_field(:sales_invoices), do: :sales_invoices_used
  defp usage_field(:bank_connections), do: :bank_connections_used

  defp build_usage_map(limits, type) do
    {used, limit} = get_usage_and_limit(limits, type)
    %{used: used, limit: limit, over_limit: used >= limit}
  end
end
