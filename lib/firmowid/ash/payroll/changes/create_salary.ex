defmodule Firmowid.Ash.Payroll.Changes.CreateSalary do
  @moduledoc "Ash change that creates a corresponding UserSalary record when an employment contract is created."
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      ash_opts =
        Enum.reject([actor: context.actor, tenant: context.tenant], fn {_k, v} -> is_nil(v) end)

      salary = Ash.Changeset.get_attribute(changeset, :salary)
      user_id = Ash.Changeset.get_attribute(changeset, :user_id)
      starts_at = Ash.Changeset.get_attribute(changeset, :starts_at)

      case Firmowid.Ash.Payroll.UserSalary
           |> Ash.Changeset.for_create(
             :create,
             %{
               hourly_rate: Money.to_decimal(salary),
               user_id: user_id,
               starts_at: starts_at
             },
             ash_opts
           )
           |> Ash.create(ash_opts) do
        {:ok, _salary} ->
          changeset

        {:error, error} ->
          Ash.Changeset.add_error(changeset, error)
      end
    end)
  end
end
