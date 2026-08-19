defmodule Firmowid.Ash.Timetracker.Session.Actions.EditCurrentUser do
  @moduledoc "Updates an unfrozen session after constraining it to the acting user."

  alias Firmowid.Ash.Timetracker.Session

  require Ash.Query

  @doc "Edits the selected session only when it belongs to the action actor."
  @spec run(Ash.ActionInput.t(), Ash.Resource.Actions.Implementation.Context.t()) ::
          {:ok, Session.t()} | {:error, term()}
  def run(input, context) do
    opts = Ash.Context.to_opts(context)

    with {:ok, session} <- current_user_session(input.arguments.id, context.actor.id, opts) do
      Ash.update(
        session,
        editable_attributes(input.arguments),
        Keyword.put(opts, :action, :update)
      )
    end
  end

  defp current_user_session(id, user_id, opts) do
    Session
    |> Ash.Query.filter(id == ^id and user_id == ^user_id)
    |> Ash.read_one(opts)
    |> case do
      {:ok, nil} -> {:error, "Session not found"}
      result -> result
    end
  end

  defp editable_attributes(arguments) do
    arguments
    |> Map.take([:title, :start_datetime, :end_datetime, :project_id, :is_remote])
    |> Enum.reject(fn {_field, value} -> is_nil(value) end)
    |> Map.new()
  end
end
