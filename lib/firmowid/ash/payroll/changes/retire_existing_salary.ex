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

      case Ash.read_one(
             Ash.Query.do_filter(
               Ash.Query.for_read(changeset.resource, :read, %{}, actor: actor, tenant: tenant),
               user_id: user_id,
               deleted_at: [is_nil: true]
             ),
             actor: actor,
             tenant: tenant,
             authorize?: false
           ) do
        {:ok, nil} ->
          changeset

        {:ok, existing} ->
          case Ash.update(
                 Ash.Changeset.for_update(existing, :retire, %{}, actor: actor, tenant: tenant),
                 actor: actor,
                 tenant: tenant,
                 authorize?: false
               ) do
            {:ok, _retired} -> changeset
            {:error, error} -> Ash.Changeset.add_error(changeset, error)
          end

        {:error, error} ->
          Ash.Changeset.add_error(changeset, error)
      end
    end)
  end
end
