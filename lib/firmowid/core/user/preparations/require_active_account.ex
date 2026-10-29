defmodule Firmowid.Core.User.Preparations.RequireActiveAccount do
  @moduledoc """
  Filters blocked accounts from authentication reads and locks sign-ins through
  token issuance to serialize with password changes. Sign-in callbacks explain
  access blocks after checking credentials; administrative reads remain unfiltered.
  """

  use Ash.Resource.Preparation

  alias Ash.Query
  alias AshAuthentication.Errors.AuthenticationFailed
  alias AshAuthentication.Info
  alias AshAuthentication.Jwt

  require Query

  @sign_in_actions [:sign_in_with_password, :sign_in_with_token, :sign_in_with_remember_me]

  @doc false
  @impl true
  @spec prepare(Query.t(), keyword(), Ash.Resource.Preparation.Context.t()) :: Query.t()
  def prepare(%{action: %{name: :sign_in_with_remember_me}} = query, _options, context) do
    query
    |> Query.lock(:for_update)
    |> Query.after_action(fn query, users ->
      # The strategy verifies the remember token before reading/locking the user.
      # A password change may revoke it while that read waits for the row lock.
      case Jwt.verify(
             Query.get_argument(query, :token),
             query.resource,
             Ash.Context.to_opts(context)
           ) do
        {:ok, _claims, _resource} -> {:ok, users}
        _ -> {:error, AuthenticationFailed.exception()}
      end
    end)
  end

  def prepare(%{action: %{name: action}} = query, _options, _context) when action in @sign_in_actions,
    do: Query.lock(query, :for_update)

  def prepare(query, _options, _context) do
    if authentication_read?(query), do: Query.filter(query, is_nil(access_block)), else: query
  end

  defp authentication_read?(query) do
    get_in(query.context, [:private, :ash_authentication?]) == true or
      match?({:ok, _strategy}, Info.strategy_for_action(query.resource, query.action.name)) or
      query.action.name == Info.authentication_get_by_subject_action_name!(query.resource)
  end
end
