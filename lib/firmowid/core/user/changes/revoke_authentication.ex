defmodule Firmowid.Core.User.Changes.RevokeAuthentication do
  @moduledoc """
  Revokes organization OAuth grants on departure and all authentication before deletion.

  Departure includes grants without an organization, but keeps other organizations'
  grants and browser sessions. Password changes use `revoke/3` to revoke everything.
  """

  use Ash.Resource.Change

  alias Ash.Resource.Change.Context
  alias Firmowid.Core.OauthAuthorizationCode
  alias Firmowid.Core.OauthConsent
  alias Firmowid.Core.OauthRefreshToken
  alias Firmowid.Core.Token

  require Ash.Query

  @doc false
  @impl true
  @spec change(Ash.Changeset.t(), keyword(), Context.t()) :: Ash.Changeset.t()
  def change(%{action_type: :destroy} = changeset, _opts, context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      case revoke(changeset.data, context) do
        :ok -> changeset
        {:error, error} -> Ash.Changeset.add_error(changeset, error)
      end
    end)
  end

  def change(changeset, _opts, context) do
    Ash.Changeset.after_action(changeset, fn changeset, user ->
      # The action has authorized the departure and locked this user row. The
      # authentication context reaches only credential resources, each filtered
      # by this user's ID.
      opts = authentication_opts(context)
      organization_id = Ash.Changeset.get_argument(changeset, :organization_id)

      with :ok <- revoke_oauth_grants(user.id, organization_id, opts) do
        {:ok, user}
      end
    end)
  end

  @doc """
  Revokes the user's browser sessions and OAuth grants within the current action.

  `keep_jti` leaves one stored token for the caller to revoke itself, such as the
  password reset token the reset action is consuming.
  """
  @spec revoke(Firmowid.Core.User.t(), Context.t(), String.t() | nil) ::
          :ok | {:error, term()}
  def revoke(user, context, keep_jti \\ nil) do
    opts = authentication_opts(context)

    with :ok <- revoke_sessions(user, keep_jti, opts) do
      revoke_oauth_grants(user.id, nil, opts)
    end
  end

  @doc false
  @impl true
  @spec atomic(Ash.Changeset.t(), keyword(), Context.t()) ::
          {:ok, Ash.Changeset.t()}
  def atomic(changeset, opts, context), do: {:ok, change(changeset, opts, context)}

  # Without the caller's tenant: the grants are filtered by organization explicitly,
  # and those issued before the organization was chosen have none.
  defp authentication_opts(context) do
    context
    |> Ash.Context.to_opts(context: %{private: %{ash_authentication?: true}})
    |> Keyword.delete(:tenant)
  end

  # Without `organization_id`, revokes the grants for every organization.
  defp revoke_oauth_grants(user_id, organization_id, opts) do
    with :ok <- revoke_refresh_tokens(user_id, organization_id, opts),
         :ok <- destroy_grants(OauthAuthorizationCode, user_id, organization_id, opts) do
      destroy_grants(OauthConsent, user_id, organization_id, opts)
    end
  end

  defp grants(resource, user_id, nil), do: Ash.Query.filter(resource, user_id == ^user_id)

  defp grants(resource, user_id, organization_id) do
    Ash.Query.filter(
      resource,
      user_id == ^user_id and (is_nil(organization_id) or organization_id == ^organization_id)
    )
  end

  defp revoke_sessions(user, keep_jti, opts) do
    # Notifications make AshAuthentication disconnect the revoked sessions' LiveViews.
    Token
    |> then(fn query ->
      if keep_jti, do: Ash.Query.filter(query, jti != ^keep_jti), else: query
    end)
    |> Ash.bulk_update(
      :revoke_all_stored_for_subject,
      %{subject: AshAuthentication.user_to_subject(user)},
      Keyword.merge(opts, notify?: true, return_errors?: true, strategy: [:atomic])
    )
    |> result()
  end

  defp revoke_refresh_tokens(user_id, organization_id, opts) do
    OauthRefreshToken
    |> grants(user_id, organization_id)
    |> Ash.Query.filter(is_nil(revoked_at))
    |> OauthRefreshToken.revoke(
      %{},
      Keyword.put(opts, :bulk_options, return_errors?: true, strategy: [:atomic])
    )
    |> result()
  end

  defp destroy_grants(resource, user_id, organization_id, opts) do
    resource
    |> grants(user_id, organization_id)
    |> Ash.bulk_destroy(
      :destroy,
      %{},
      Keyword.merge(opts, return_errors?: true, strategy: [:atomic])
    )
    |> result()
  end

  defp result(%Ash.BulkResult{status: :success}), do: :ok
  defp result(%Ash.BulkResult{errors: errors}), do: {:error, Ash.Error.to_error_class(errors)}
end
