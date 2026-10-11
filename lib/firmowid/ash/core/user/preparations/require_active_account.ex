defmodule Firmowid.Ash.Core.User.Preparations.RequireActiveAccount do
  @moduledoc "Excludes archived accounts from authentication reads without hiding them from administrators."

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

  def prepare(query, _options, _context), do: filter_archived_accounts(query, authentication_read?(query))

  defp filter_archived_accounts(query, true), do: Query.filter(query, is_nil(archived_at))
  defp filter_archived_accounts(query, false), do: query

  defp authentication_read?(query) do
    get_in(query.context, [:private, :ash_authentication?]) == true or
      match?({:ok, _strategy}, Info.strategy_for_action(query.resource, query.action.name)) or
      query.action.name == Info.authentication_get_by_subject_action_name!(query.resource)
  end
end
