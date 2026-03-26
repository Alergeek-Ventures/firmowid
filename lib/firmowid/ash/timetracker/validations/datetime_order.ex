defmodule Firmowid.Ash.Timetracker.Validations.DatetimeOrder do
  @moduledoc """
  Validates that `start_datetime` is before `end_datetime` when both are present.
  """
  use Ash.Resource.Validation

  alias Ash.Error.Changes.InvalidAttribute

  @impl true
  def init(opts) do
    {:ok, opts}
  end

  @impl true
  def validate(changeset, opts, _context) do
    start_field = opts[:start_field] || :start_datetime
    end_field = opts[:end_field] || :end_datetime

    start_dt = Ash.Changeset.get_attribute(changeset, start_field)
    end_dt = Ash.Changeset.get_attribute(changeset, end_field)

    if end_dt && start_dt && DateTime.after?(start_dt, end_dt) do
      {:error,
       InvalidAttribute.exception(
         field: start_field,
         message: "must be before end datetime"
       )}
    else
      :ok
    end
  end
end
