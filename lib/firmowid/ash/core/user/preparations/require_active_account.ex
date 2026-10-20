defmodule Firmowid.Ash.Core.User.Preparations.RequireActiveAccount do
  @moduledoc """
  Excludes blocked accounts (see the User `:access_block` calculation) from
  authentication reads, so no session, bearer token or widget token can act for them,
  without hiding them from administrators.

  Sign-in actions exclude only archived accounts: a member of an organization without
  a billing plan signs in successfully, and the sign-in callback explains the block
  instead of issuing a session, so the reason is shown only after the password check.
  """

  use Ash.Resource.Preparation

  alias Ash.Query
  alias AshAuthentication.Info

  require Query

  @sign_in_actions [:sign_in_with_password, :sign_in_with_token, :sign_in_with_remember_me]

  @doc false
  @impl true
  @spec prepare(Query.t(), keyword(), Ash.Resource.Preparation.Context.t()) :: Query.t()
  def prepare(%{action: %{name: action}} = query, _options, _context) when action in @sign_in_actions do
    query
    |> Query.lock(:for_update)
    |> Query.filter(is_nil(archived_at))
  end

  def prepare(query, _options, _context), do: filter_blocked_accounts(query, authentication_read?(query))

  defp filter_blocked_accounts(query, true), do: Query.filter(query, is_nil(access_block))
  defp filter_blocked_accounts(query, false), do: query

  defp authentication_read?(query) do
    get_in(query.context, [:private, :ash_authentication?]) == true or
      match?({:ok, _strategy}, Info.strategy_for_action(query.resource, query.action.name)) or
      query.action.name == Info.authentication_get_by_subject_action_name!(query.resource)
  end
end
