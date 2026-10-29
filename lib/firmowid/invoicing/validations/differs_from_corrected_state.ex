defmodule Firmowid.Invoicing.Validations.DiffersFromCorrectedState do
  @moduledoc """
  Passes when a correction changes `:field` from the state it corrects.

  Used as a `where` condition, so a correction only rederives a value from a field the
  user changed and keeps what the corrected invoice carries, e.g. cash accounting
  imported from KSeF. `PrepareCorrection` stores that state as `invoice_reference`;
  without it (no original chosen yet) the condition passes.
  """
  use Ash.Resource.Validation

  @doc "Compares the changeset's `:field` with the corrected state's value."
  @spec validate(Ash.Changeset.t(), keyword(), Ash.Resource.Validation.Context.t()) ::
          :ok | {:error, keyword()}
  @impl true
  def validate(changeset, opts, _context) do
    field = Keyword.fetch!(opts, :field)

    case changeset.context[:invoice_reference] do
      %{^field => value} ->
        if Ash.Changeset.get_attribute(changeset, field) == value,
          do: {:error, field: field, message: "is unchanged"},
          else: :ok

      _no_reference ->
        :ok
    end
  end
end
