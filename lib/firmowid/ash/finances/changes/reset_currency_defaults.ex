defmodule Firmowid.Ash.Finances.Changes.ResetCurrencyDefaults do
  @moduledoc """
  Resets all same-currency accounts' `is_default` to `false` within the
  same tenant before the current record is marked as the new default.

  Applied conditionally via `where:` in the resource DSL — only runs when
  `is_default` is being set to `true`.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      currency = Ash.Changeset.get_attribute(changeset, :currency)

      case Ash.bulk_update(
             changeset.resource,
             :clear_default,
             %{},
             actor: context.actor,
             tenant: changeset.tenant,
             return_errors?: true,
             strategy: [:stream],
             allow_stream_with: :full_read,
             filter: [currency: currency]
           ) do
        %Ash.BulkResult{status: :success} -> changeset
        %Ash.BulkResult{errors: errors} -> Ash.Changeset.add_error(changeset, errors)
      end
    end)
  end
end
