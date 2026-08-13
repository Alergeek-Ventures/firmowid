defmodule Firmowid.Ash.Payroll.Changes.SkipUnchangedRate do
  @moduledoc """
  Skips inserting a new salary when the hourly rate matches the user's current one, to avoid duplicates in salary history.
  """
  use Ash.Resource.Change

  alias Firmowid.Ash.Payroll

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      user_id = Ash.Changeset.get_attribute(changeset, :user_id)
      new_rate = Ash.Changeset.get_attribute(changeset, :hourly_rate)

      salary = current_salary(user_id, context)

      if salary && Decimal.equal?(salary.hourly_rate, new_rate) do
        Ash.Changeset.set_result(changeset, {:ok, salary})
      else
        changeset
      end
    end)
  end

  defp current_salary(user_id, context) do
    opts = Ash.Context.to_opts(context)

    %{user_id: user_id, active_at: Date.utc_today()}
    |> Payroll.query_to_list_salaries(opts)
    |> Ash.Query.limit(1)
    |> Ash.read_one!(opts)
  end
end
