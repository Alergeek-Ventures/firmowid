defmodule Firmowid.Ash.Core.User.Changes.RevokeAuthentication do
  @moduledoc "Revokes browser sessions and OAuth grants in the authorized account archive transaction."

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
    Ash.Changeset.after_action(changeset, fn _changeset, user ->
      # Archive has already been authorized and has locked this user row. The
      # authentication context grants access only to the credential resources;
      # every operation below is constrained to the archived user's ID.
      with :ok <- revoke(user, context) do
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
    opts = Ash.Context.to_opts(context, context: %{private: %{ash_authentication?: true}})

    with :ok <- revoke_sessions(user, keep_jti, opts),
         :ok <- revoke_refresh_tokens(user.id, opts),
         :ok <- destroy_grants(OauthAuthorizationCode, user.id, opts) do
      destroy_grants(OauthConsent, user.id, opts)
    end
  end

  @doc false
  @impl true
  @spec atomic(Ash.Changeset.t(), keyword(), Context.t()) ::
          {:ok, Ash.Changeset.t()}
  def atomic(changeset, opts, context), do: {:ok, change(changeset, opts, context)}

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

  defp revoke_refresh_tokens(user_id, opts) do
    OauthRefreshToken
    |> Ash.Query.filter(user_id == ^user_id and is_nil(revoked_at))
    |> OauthRefreshToken.revoke(
      %{},
      Keyword.put(opts, :bulk_options, return_errors?: true, strategy: [:atomic])
    )
    |> result()
  end

  defp destroy_grants(resource, user_id, opts) do
    resource
    |> Ash.Query.filter(user_id == ^user_id)
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
