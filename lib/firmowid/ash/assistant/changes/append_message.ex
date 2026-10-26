defmodule Firmowid.Ash.Assistant.Changes.AppendMessage do
  @moduledoc "Creates a user message through the session in the same transaction as its job."
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    text = Ash.Changeset.get_argument(changeset, :text)

    changeset
    |> Ash.Changeset.force_change_attribute(
      :title,
      Ash.Changeset.get_attribute(changeset, :title) || String.slice(text, 0, 100)
    )
    |> Ash.Changeset.manage_relationship(
      :messages,
      %{role: :user, parts: [%{"type" => "text", "text" => text}]},
      type: :create
    )
  end
end
