defmodule Firmowid.Ash.Core.Argon2Provider do
  @moduledoc """
  AshAuthentication hash provider using Argon2.

  Drop-in replacement for `AshAuthentication.BcryptProvider` for apps that
  already use `argon2_elixir`. Existing `$argon2id$...` password hashes work
  unchanged — no re-hashing needed.
  """
  @behaviour AshAuthentication.HashProvider

  @impl true
  @spec hash(String.t()) :: {:ok, String.t()} | :error
  def hash(input) when is_binary(input), do: {:ok, Argon2.hash_pwd_salt(input)}
  def hash(_), do: :error

  @impl true
  @spec valid?(String.t() | nil, String.t()) :: boolean()
  def valid?(nil, _hash), do: Argon2.no_user_verify()

  def valid?(input, hash) when is_binary(input) and is_binary(hash), do: Argon2.verify_pass(input, hash)

  @impl true
  @spec simulate() :: false
  def simulate, do: Argon2.no_user_verify()
end
