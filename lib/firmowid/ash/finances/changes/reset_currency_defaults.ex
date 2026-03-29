defmodule Firmowid.Ash.Finances.Changes.ResetCurrencyDefaults do
  @moduledoc """
  Before setting a bank account as default, resets all other same-currency
  accounts' `is_default` to `false` within the same tenant.

  Runs as a `before_action` hook so both the reset and the update happen
  in the same database transaction. Follows the same pattern as
  `Firmowid.Ash.Payroll.Changes.RetireExistingSalary`.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      currency = Ash.Changeset.get_attribute(changeset, :currency)
      tenant = changeset.tenant
      actor = context.actor

      case reset_other_defaults(changeset.resource, currency, actor, tenant) do
        :ok ->
          changeset

        {:error, error} ->
          Ash.Changeset.add_error(changeset, error)
      end
    end)
  end

  defp reset_other_defaults(resource, currency, actor, tenant) do
    # authorize?: false — the change runs inside :make_default which is
    # already authorized (admin bypass). Skipping re-authorization avoids
    # policy recursion on the internal bulk update.
    result =
      resource
      |> Ash.Query.for_read(:read, %{}, actor: actor, tenant: tenant)
      |> Ash.Query.do_filter(currency: currency, is_default: true)
      |> Ash.bulk_update(:update, %{is_default: false},
        actor: actor,
        tenant: tenant,
        authorize?: false,
        return_errors?: true
      )

    case result do
      %Ash.BulkResult{status: :success} -> :ok
      %Ash.BulkResult{errors: errors} -> {:error, errors}
    end
  end
end
