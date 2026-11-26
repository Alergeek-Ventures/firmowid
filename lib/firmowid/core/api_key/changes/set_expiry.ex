defmodule Firmowid.Core.ApiKey.Changes.SetExpiry do
  @moduledoc """
  Makes a key work through the `expires_on` date, Polish time, or until it is revoked when the
  date is nil. The date must be after today, so a new key always works.
  """

  use Ash.Resource.Change

  alias Firmowid.LocalDate

  @impl true
  def change(changeset, _opts, _context) do
    case Ash.Changeset.get_argument(changeset, :expires_on) do
      nil ->
        changeset

      expires_on ->
        if Date.after?(expires_on, LocalDate.today()) do
          Ash.Changeset.change_attribute(changeset, :expires_at, LocalDate.end_of(expires_on))
        else
          Ash.Changeset.add_error(changeset, field: :expires_on, message: "must be after today")
        end
    end
  end
end
