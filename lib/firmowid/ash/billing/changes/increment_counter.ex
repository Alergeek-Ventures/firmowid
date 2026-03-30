defmodule Firmowid.Ash.Billing.Changes.IncrementCounter do
  @moduledoc """
  Atomically increments the usage counter for the resource type given by
  the `:type` argument.

  Generates `SET field = field + 1` at the database level — no read required,
  no race condition under concurrency.
  """
  use Ash.Resource.Change

  import Ash.Expr

  @impl true
  def change(changeset, _opts, _context) do
    field = usage_field(Ash.Changeset.get_argument(changeset, :type))
    Ash.Changeset.atomic_update(changeset, field, expr(^atomic_ref(field) + 1))
  end

  @impl true
  def atomic(changeset, _opts, _context) do
    field = usage_field(Ash.Changeset.get_argument(changeset, :type))
    {:atomic, %{field => expr(^atomic_ref(field) + 1)}}
  end

  defp usage_field(:cost_invoices), do: :cost_invoices_used
  defp usage_field(:sales_invoices), do: :sales_invoices_used
  defp usage_field(:bank_connections), do: :bank_connections_used
end
