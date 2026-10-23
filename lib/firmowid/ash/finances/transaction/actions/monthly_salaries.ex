defmodule Firmowid.Ash.Finances.Transaction.Actions.MonthlySalaries do
  @moduledoc "Lists every employee salary of one month with its hours record state and paying transfer, without ranking filters."

  use Ash.Resource.Actions.Implementation

  alias Firmowid.Ash.Finances
  alias Firmowid.Ash.Payroll
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.Timetracker

  @impl true
  def run(input, _opts, context) do
    scope = Scope.new!(context.actor, context.tenant)
    month = Date.beginning_of_month(input.arguments.month)
    query = input.arguments[:query] && normalize(input.arguments.query)

    hours_statuses =
      %{month: month.month, year: month.year, submission_status: nil}
      |> Timetracker.list_hours_records!(load: [:member], scope: scope)
      |> Enum.group_by(& &1.member.user_id, & &1.submission_status)

    transaction_ids =
      %{salary_month: month}
      |> Finances.list_transactions!(scope: scope)
      |> Map.new(&{&1.salary_user_id, &1.id})

    {:ok,
     %{active_at: Date.end_of_month(month), user_id: input.arguments[:user_id]}
     |> Payroll.list_salaries!(
       load: [member: :user, monthly_amount: [month: month], payout_estimates: [month: month]],
       query: [filter: [member: [archived_at: [is_nil: true]]]],
       scope: scope
     )
     |> Enum.reject(&is_nil(&1.member.user))
     |> Enum.map(fn %{member: %{user: user}} = salary ->
       %{
         user_id: user.id,
         name: salary.member.name || to_string(user.email),
         month: month,
         hourly_rate: salary.hourly_rate,
         expected_amount: salary.monthly_amount,
         payout_estimates: salary.payout_estimates,
         hours_submission_status: hours_status(Map.get(hours_statuses, user.id, [])),
         connected_transaction_id: Map.get(transaction_ids, user.id)
       }
     end)
     |> Enum.filter(&(is_nil(query) or String.contains?(normalize(&1.name), query)))
     |> Enum.sort_by(& &1.name)}
  end

  defp hours_status(statuses) do
    cond do
      :submitted in statuses -> :submitted
      :withdrawn in statuses -> :withdrawn
      true -> :missing
    end
  end

  defp normalize(text), do: text |> AnyAscii.transliterate() |> IO.iodata_to_binary() |> String.downcase()
end
