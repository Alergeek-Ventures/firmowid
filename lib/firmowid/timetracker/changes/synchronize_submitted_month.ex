defmodule Firmowid.Timetracker.Changes.SynchronizeSubmittedMonth do
  @moduledoc "Orders authored session changes against hours-record submission through the member row."
  use Ash.Resource.Change

  alias Ash.Resource.Change.GetAndLockForUpdate
  alias Firmowid.Checks.ActorRole
  alias Firmowid.Core.Member
  alias Firmowid.Core.User
  alias Firmowid.Timetracker.Checks.HoursRecordNotSubmitted

  @impl true
  def change(changeset, _opts, context) do
    if match?(%User{}, context.actor) do
      changeset =
        Ash.Changeset.before_action(changeset, fn changeset ->
          lock_member!(
            Ash.Changeset.get_attribute(changeset, :member_id),
            Ash.Context.to_opts(context)
          )

          changeset
        end)

      changeset =
        if changeset.action_type == :create,
          do: changeset,
          else: GetAndLockForUpdate.change(changeset, [], context)

      Ash.Changeset.before_action(changeset, fn changeset ->
        if ActorRole.role(context.actor) == :admin do
          changeset
        else
          case HoursRecordNotSubmitted.match?(context.actor, %{subject: changeset}, []) do
            {:ok, true} -> changeset
            {:ok, false} -> Ash.Changeset.add_error(changeset, Ash.Error.Forbidden.exception())
          end
        end
      end)
    else
      changeset
    end
  end

  @doc "Locks the member before session rows; hours-record FK inserts take a conflicting key-share lock."
  @spec lock_member!(Ash.UUID.t(), keyword()) :: :ok
  def lock_member!(member_id, opts) do
    Ash.get!(Member, member_id, Keyword.put(opts, :lock, :for_update))
    :ok
  end
end
