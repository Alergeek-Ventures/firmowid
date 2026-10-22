defmodule Firmowid.Ash.Core.User.Changes.RevokeAuthentication do
  @moduledoc """
  Revokes the account's OAuth grants when it leaves an organization.

  Only the grants for that organization go, with those issued before the
  organization was chosen on the consent screen, which work in the default one.
  Grants for the account's other organizations and browser sessions stay: the
  account keeps signing in. `revoke/3` revokes all grants and the sessions, for
  a password reset.
  """

  use Ash.Resource.Change

  alias Ash.Resource.Change.Context
  alias Firmowid.Ash.Core.OauthAuthorizationCode
  alias Firmowid.Ash.Core.OauthConsent
  alias Firmowid.Ash.Core.OauthRefreshToken
  alias Firmowid.Ash.Core.Token

  require Ash.Query

  @doc false
  @impl true
  @spec change(Ash.Changeset.t(), keyword(), Context.t()) :: Ash.Changeset.t()
  def change(changeset, _opts, context) do
    Ash.Changeset.after_action(changeset, fn changeset, user ->
      # Leaving the organization has already been authorized and has locked this
      # user row. The authentication context grants access only to the credential
      # resources; every operation below is constrained to this user's ID.
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
  @spec revoke(Firmowid.Ash.Core.User.t(), Context.t(), String.t() | nil) ::
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
