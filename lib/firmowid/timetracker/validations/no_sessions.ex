defmodule Firmowid.Timetracker.Validations.NoSessions do
  @moduledoc "Refuses to delete a project with recorded time, so no session loses its project."
  use Ash.Resource.Validation
  use Gettext, backend: Firmowid.Gettext

  alias Ash.Error.Changes.InvalidChanges

  @impl true
  def validate(changeset, _opts, context) do
    # The aggregate sees every employee's sessions, not only those the actor may read.
    case Ash.load(changeset.data, :first_session_at, Ash.Context.to_opts(context)) do
      {:ok, %{first_session_at: nil}} ->
        :ok

      {:ok, _project} ->
        {:error, InvalidChanges.exception(message: gettext_noop("A project with recorded time cannot be deleted."))}

      {:error, error} ->
        {:error, error}
    end
  end
end
