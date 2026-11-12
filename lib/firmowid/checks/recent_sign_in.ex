defmodule Firmowid.Checks.RecentSignIn do
  @moduledoc """
  Whether the actor's session was signed in within the last 10 minutes, so an
  irreversible action proves it is the account's holder and not someone with a
  stolen session.

  The time is the `iat` claim of the session token (see the `:token_claims` metadata
  `FirmowidWeb.Infrastructure.UserAuth.load_member/2` puts on the user), which every
  sign-in mints anew. A session restored from the remember-me cookie carries the
  `"remembered"` claim (see the User `:sign_in_with_remember_me` action) and does not
  count: no credential was given.
  """
  use Ash.Policy.SimpleCheck

  @max_age_seconds 10 * 60

  @impl true
  def describe(_opts), do: "the actor signed in within the last 10 minutes"

  @impl true
  def match?(%{__metadata__: %{token_claims: %{"iat" => issued_at} = claims}}, _context, _opts) do
    not Map.has_key?(claims, "remembered") and
      System.system_time(:second) - issued_at <= @max_age_seconds
  end

  def match?(_actor, _context, _opts), do: false
end
