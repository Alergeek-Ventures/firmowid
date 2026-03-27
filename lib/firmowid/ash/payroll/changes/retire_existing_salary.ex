defmodule Firmowid.Ash.Payroll.Changes.RetireExistingSalary do
  @moduledoc """
  Before creating a new salary, retires any existing active salary for the user.

  Runs as a `before_action` hook so both the retire and create happen in the
  same database transaction. Looks up the current active salary (where
  `deleted_at IS NULL`) and calls the `:retire` update action on it.
  """
  use Ash.Resource.Change

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      user_id = Ash.Changeset.get_attribute(changeset, :user_id)
      tenant = changeset.tenant
      actor = context.actor

      case find_active_salary(changeset.resource, user_id, actor, tenant) do
        {:ok, nil} ->
          changeset

        {:ok, existing} ->
          retire_salary(changeset, existing, actor, tenant)

        {:error, error} ->
          Ash.Changeset.add_error(changeset, error)
      end
    end)
  end

  defp find_active_salary(resource, user_id, actor, tenant) do
    resource
    |> Ash.Query.for_read(:read, %{}, actor: actor, tenant: tenant)
    |> Ash.Query.do_filter(user_id: user_id, deleted_at: [is_nil: true])
    # TODO: migrate away from authorize?: false — the change runs inside
    # :create_with_retire which is already authorized; skipping re-authorization
    # avoids policy recursion. Replace with a dedicated internal read action.
    |> Ash.read_one(actor: actor, tenant: tenant, authorize?: false)
  end

  defp retire_salary(changeset, existing, actor, tenant) do
    # TODO: migrate away from authorize?: false — same as above; the retire
    # runs within an already-authorized :create_with_retire transaction.
    case Ash.update(
           Ash.Changeset.for_update(existing, :retire, %{}, actor: actor, tenant: tenant),
           actor: actor,
           tenant: tenant,
           authorize?: false
         ) do
      {:ok, _retired} -> changeset
      {:error, error} -> Ash.Changeset.add_error(changeset, error)
    end
  end
end
