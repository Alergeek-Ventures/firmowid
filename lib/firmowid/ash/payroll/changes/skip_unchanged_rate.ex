defmodule Firmowid.Ash.Payroll.Changes.SkipUnchangedRate do
  @moduledoc """
  Skips inserting a new salary when the hourly rate matches the member's current one, to avoid duplicates in salary history.
  """
  use Ash.Resource.Change

  alias Firmowid.Ash.Payroll

  require Ash.Query

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      member_id = Ash.Changeset.get_attribute(changeset, :member_id)
      new_rate = Ash.Changeset.get_attribute(changeset, :hourly_rate)

      salary = current_salary(member_id, context)

      if salary && Decimal.equal?(salary.hourly_rate, new_rate) do
        Ash.Changeset.set_result(changeset, {:ok, salary})
      else
        changeset
      end
    end)
  end

  defp current_salary(member_id, context) do
    opts = Ash.Context.to_opts(context)

    %{active_at: Date.utc_today()}
    |> Payroll.query_to_list_salaries(opts)
    |> Ash.Query.filter(member_id == ^member_id)
    |> Ash.Query.limit(1)
    |> Ash.read_one!(opts)
  end
end
