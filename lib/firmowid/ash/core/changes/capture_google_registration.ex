defmodule Firmowid.Ash.Core.Changes.CaptureGoogleRegistration do
  @moduledoc "Captures a Google account creation only after a successful user insert."

  use Ash.Resource.Change

  alias Firmowid.Analytics

  @doc false
  @spec change(Ash.Changeset.t(), keyword(), Ash.Resource.Change.context()) :: Ash.Changeset.t()
  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_transaction(changeset, fn
      _changeset, {:ok, user} = result ->
        if !Ash.Resource.get_metadata(user, :upsert_skipped) do
          Analytics.capture_account_created(user, :google)
        end

        result

      _changeset, error ->
        error
    end)
  end
end
