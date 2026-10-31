defmodule Firmowid.Timetracker.Session.Actions.EditCurrentUser do
  @moduledoc "Updates an unfrozen session after constraining it to the acting user."

  alias Firmowid.Timetracker.Checks.HoursRecordNotSubmitted
  alias Firmowid.Timetracker.Session

  @doc "Edits the selected session only when it belongs to the action actor."
  @spec run(Ash.ActionInput.t(), Ash.Resource.Actions.Implementation.Context.t()) ::
          {:ok, Session.t()} | {:error, term()}
  def run(input, context) do
    opts = Ash.Context.to_opts(context)

    with {:ok, session} <- Session.current_session(input.arguments.id, opts) do
      changeset =
        session
        |> Ash.Changeset.for_update(:update, editable_attributes(input.arguments), opts)
        |> Ash.Changeset.before_action(fn changeset ->
          case HoursRecordNotSubmitted.match?(context.actor, %{subject: changeset}, []) do
            {:ok, true} ->
              changeset

            {:ok, false} ->
              Ash.Changeset.add_error(
                changeset,
                Ash.Error.Forbidden.exception(action_input: input)
              )
          end
        end)

      Ash.update(changeset, opts)
    end
  end

  defp editable_attributes(arguments) do
    arguments
    |> Map.take([:title, :start_datetime, :end_datetime, :project_id, :is_remote])
    |> Enum.reject(fn {_field, value} -> is_nil(value) end)
    |> Map.new()
  end
end
