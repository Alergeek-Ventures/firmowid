defmodule Firmowid.Ash.Ksef.Changes.SetCredentialExpiration do
  @moduledoc """
  Persists non-sensitive expiration metadata from KSeF credential material.
  """

  use Ash.Resource.Change

  alias Firmowid.Ash.Ksef.CredentialMetadata

  @impl true
  def change(changeset, _opts, _context) do
    expires_on =
      CredentialMetadata.expires_on(%{
        auth_type: Ash.Changeset.get_attribute(changeset, :auth_type),
        credentials: Ash.Changeset.get_attribute(changeset, :credentials)
      })

    Ash.Changeset.force_change_attribute(changeset, :expires_on, expires_on)
  end
end
