defmodule Firmowid.Ash.Billing.Changes.DecrementCounter do
  @moduledoc """
  Atomically decrements the usage counter for the resource type given by
  the `:type` argument, floored at zero.

  Generates `SET field = CASE WHEN field > 0 THEN field - 1 ELSE 0 END`
  at the database level — no race condition under concurrency.
  """
  use Ash.Resource.Change

  import Ash.Expr

  @impl true
  def change(changeset, _opts, _context) do
    field = usage_field(Ash.Changeset.get_argument(changeset, :type))

    Ash.Changeset.atomic_update(
      changeset,
      field,
      expr(
        if ^atomic_ref(field) > 0 do
          ^atomic_ref(field) - 1
        else
          0
        end
      )
    )
  end

  @impl true
  def atomic(changeset, _opts, _context) do
    field = usage_field(Ash.Changeset.get_argument(changeset, :type))

    {:atomic,
     %{
       field =>
         expr(
           if ^atomic_ref(field) > 0 do
             ^atomic_ref(field) - 1
           else
             0
           end
         )
     }}
  end

  defp usage_field(:cost_invoices), do: :cost_invoices_used
  defp usage_field(:sales_invoices), do: :sales_invoices_used
  defp usage_field(:bank_connections), do: :bank_connections_used
end
