defmodule Firmowid.Ash.Payroll.Actions.CalculatePayout do
  @moduledoc "Combines an employee's effective declarations with explicit inputs for one payout."
  use Ash.Resource.Actions.Implementation

  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Payroll
  alias Firmowid.Ash.Payroll.PayoutCalculation
  alias Firmowid.Ash.Scope

  @impl true
  def run(input, _opts, context) do
    scope = Scope.new!(context.actor, context.tenant)
    arguments = Map.new(input.action.arguments, &{&1.name, Map.get(input.arguments, &1.name)})

    with {:ok, member} <- Core.get_member(arguments.member_id, scope: scope) do
      declarations =
        if arguments.payout_date do
          Payroll.list_tax_declarations!(
            %{member_id: member.id, as_of: arguments.payout_date},
            scope: scope
          )
        else
          []
        end

      inputs = Map.put(arguments, :birthday, member.birthday)
      {:ok, PayoutCalculation.calculate(List.first(declarations), inputs)}
    end
  end
end
