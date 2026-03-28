defmodule Firmowid.Ash.Analysis.Validations.KindTagDefinitionConsistency do
  @moduledoc """
  Validates that `kind` and `tag_definition_id` are consistent on an `EntityTag`:

    * `:project` kind requires a non-nil `tag_definition_id`
    * `:company` and `:internal` kinds require a nil `tag_definition_id`

  This mirrors the database CHECK constraint
  `(kind = 'project' AND tag_definition_id IS NOT NULL) OR (kind != 'project' AND tag_definition_id IS NULL)`.
  """
  use Ash.Resource.Validation

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def validate(changeset, _opts, _context) do
    kind = Ash.Changeset.get_attribute(changeset, :kind)
    tag_def_id = Ash.Changeset.get_attribute(changeset, :tag_definition_id)

    cond do
      kind == :project and is_nil(tag_def_id) ->
        {:error, field: :tag_definition_id, message: "is required for project tags"}

      kind != :project and not is_nil(tag_def_id) ->
        {:error, field: :tag_definition_id, message: "must be empty for built-in tag kinds"}

      true ->
        :ok
    end
  end
end
