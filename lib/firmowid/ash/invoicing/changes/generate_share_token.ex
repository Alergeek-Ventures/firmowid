defmodule Firmowid.Ash.Invoicing.Changes.GenerateShareToken do
  @moduledoc """
  Ash change that generates a share token for a sales invoice.

  If `share_token` is already set, does nothing. Otherwise generates
  a 32-byte cryptographically secure random token.
  """
  use Ash.Resource.Change

  @token_bytes 32

  @impl true
  def change(changeset, _opts, _context) do
    current_token = Ash.Changeset.get_data(changeset, :share_token)

    if is_binary(current_token) and current_token != "" do
      changeset
    else
      token =
        @token_bytes
        |> :crypto.strong_rand_bytes()
        |> Base.url_encode64(padding: false)

      Ash.Changeset.force_change_attribute(changeset, :share_token, token)
    end
  end
end
