defmodule Firmowid.Ash.Timetracker.Session.Actions.EditCurrentUser do
  @moduledoc "Updates an unfrozen session after constraining it to the acting user."

  alias Firmowid.Ash.Timetracker.Session

  @doc "Edits the selected session only when it belongs to the action actor."
  @spec run(Ash.ActionInput.t(), Ash.Resource.Actions.Implementation.Context.t()) ::
          {:ok, Session.t()} | {:error, term()}
  def run(input, context) do
    opts = Ash.Context.to_opts(context)

    with {:ok, session} <- Session.current_session(input.arguments.id, opts) do
      Ash.update(
        session,
        editable_attributes(input.arguments),
        Keyword.put(opts, :action, :update)
      )
    end
  end

  defp editable_attributes(arguments) do
    arguments
    |> Map.take([:title, :start_datetime, :end_datetime, :project_id, :is_remote])
    |> Enum.reject(fn {_field, value} -> is_nil(value) end)
    |> Map.new()
  end
end
