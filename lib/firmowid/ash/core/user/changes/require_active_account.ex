defmodule Firmowid.Ash.Core.User.Changes.RequireActiveAccount do
  @moduledoc "Rejects archived authentication results before tokens or provider side effects are produced."

  use Ash.Resource.Change

  alias Ash.Changeset
  alias Ash.Resource.Change.Context
  alias AshAuthentication.Errors.AuthenticationFailed
  alias AshAuthentication.Info
  alias AshAuthentication.Strategy.OAuth2
  alias AshAuthentication.UserIdentity
  alias Firmowid.Ash.Core.User
  alias Firmowid.Ash.SystemActor

  @doc false
  @impl true
  @spec change(Changeset.t(), keyword(), Context.t()) :: Changeset.t()
  def change(%{context: %{private: %{ash_authentication?: true}}} = changeset, _options, context),
    do: require_active_account(changeset, context)

  def change(changeset, _options, context) do
    case Info.strategy_for_action(changeset.resource, changeset.action.name) do
      {:ok, _strategy} -> require_active_account(changeset, context)
      :error -> changeset
    end
  end

  @doc false
  @impl true
  @spec atomic(Changeset.t(), keyword(), Context.t()) :: {:ok, Changeset.t()}
  def atomic(changeset, options, context), do: {:ok, change(changeset, options, context)}

  defp require_active_account(changeset, context) do
    changeset
    |> reject_archived_data()
    |> guard_existing_identity(context)
    # Skipped OAuth upserts return the existing account only after the data-layer action.
    |> Changeset.after_action(&require_active_result/2, prepend?: true)
  end

  defp reject_archived_data(%{data: %{archived_at: archived_at}} = changeset) when not is_nil(archived_at) do
    Changeset.add_error(changeset, AuthenticationFailed.exception())
  end

  defp reject_archived_data(changeset), do: changeset

  defp guard_existing_identity(changeset, context) do
    case Info.strategy_for_action(changeset.resource, changeset.action.name) do
      {:ok, %{identity_resource: resource} = strategy} when not is_nil(resource) ->
        Changeset.before_action(
          changeset,
          &require_active_identity(&1, strategy, context),
          prepend?: true
        )

      _ ->
        changeset
    end
  end

  defp require_active_identity(changeset, strategy, context) do
    user_info = Changeset.get_argument(changeset, :user_info)

    with {:ok, strategy} <-
           OAuth2.put_connection_id(
             strategy,
             OAuth2.connection_id_from_context(changeset.context)
           ),
         uid when not is_nil(uid) <- OAuth2.uid_from_user_info(user_info),
         {:ok, identity} <-
           OAuth2.UserResolver.fetch_identity(strategy, uid,
             actor: context.actor,
             tenant: context.tenant
           ) do
      config = UserIdentity.Info.user_identity_options(strategy.identity_resource)
      user_id = Map.fetch!(identity, config.user_id_attribute_name)

      # Resolver authentication reads hide archived users and treat their identities as orphaned.
      # This internal eligibility check must inspect the persisted account, not authenticate it.
      # Keep the owner locked until registration commits, before the resolver reloads it.
      case User.get(user_id,
             query: Ash.Query.lock(User, :for_update),
             actor: %SystemActor{
               role: :authentication_identity_reader,
               org_id: nil,
               user_id: user_id
             },
             context: %{private: %{ash_authentication?: false}},
             not_found_error?: false
           ) do
        {:ok, nil} -> changeset
        {:ok, %{archived_at: nil}} -> changeset
        {:ok, _archived_user} -> Changeset.add_error(changeset, AuthenticationFailed.exception())
        {:error, _error} -> Changeset.add_error(changeset, AuthenticationFailed.exception())
      end
    else
      # The provider resolver remains responsible for missing, invalid, or unlinked identities.
      :error -> changeset
      nil -> changeset
    end
  end

  defp require_active_result(_changeset, %{archived_at: nil} = user), do: {:ok, user}

  defp require_active_result(_changeset, _user), do: {:error, AuthenticationFailed.exception()}
end
