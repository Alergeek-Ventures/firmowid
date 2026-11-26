defmodule FirmowidWeb.Timetracker.Utilities.MoveSessionForm do
  @moduledoc false
  use Ecto.Schema
  use Gettext, backend: Firmowid.Gettext

  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :title, :string
  end

  def changeset(attrs \\ %{}, opts \\ []) do
    changeset(%__MODULE__{}, attrs, opts)
  end

  def changeset(form, attrs, opts) do
    current_title = Keyword.get(opts, :current_title)

    form
    |> cast(attrs, [:title])
    |> update_change(:title, &String.trim/1)
    |> validate_required([:title])
    |> validate_different(current_title)
  end

  defp validate_different(changeset, nil), do: changeset

  # A rename to the current name would leave the session in its task.
  defp validate_different(changeset, current_title) do
    validate_change(changeset, :title, fn :title, title ->
      if title == current_title,
        do: [title: gettext_noop("must be different from the current name")],
        else: []
    end)
  end
end
