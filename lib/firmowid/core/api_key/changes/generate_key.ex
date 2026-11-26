defmodule Firmowid.Core.ApiKey.Changes.GenerateKey do
  @moduledoc """
  Generates the secret of a new key: the prefix and 32 random bytes. Only its SHA-256 is
  stored, and a request finds its key by that hash (see `hash/1`). The secret itself is in the
  `plaintext_api_key` metadata of the created key, the only time it is shown.

  ash_authentication's `api_key` strategy signs keys in for one resource, while a key here acts
  as a `User` or as a `ServiceAccount`; giving `ServiceAccount` a strategy too would make it an
  authenticated resource that the browser sign-in and sign-out also go through.

  ## Options

  - `prefix` — what the key starts with, before `_` (required)
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, opts, _context) do
    key =
      "#{Keyword.fetch!(opts, :prefix)}_" <>
        Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

    changeset
    |> Ash.Changeset.force_change_attribute(:api_key_hash, hash(key))
    |> Ash.Changeset.after_action(fn _changeset, api_key ->
      {:ok, Ash.Resource.put_metadata(api_key, :plaintext_api_key, key)}
    end)
  end

  @doc "Returns the stored hash of a key."
  @spec hash(String.t()) :: binary()
  def hash(key), do: :crypto.hash(:sha256, key)
end
