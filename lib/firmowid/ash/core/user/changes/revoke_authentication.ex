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
      opts = Ash.Context.to_opts(context, context: %{private: %{ash_authentication?: true}})

      with :ok <- revoke_sessions(user, opts),
           :ok <- revoke_refresh_tokens(user.id, opts),
           :ok <- destroy_grants(OauthAuthorizationCode, user.id, opts),
           :ok <- destroy_grants(OauthConsent, user.id, opts) do
        {:ok, user}
      end
    end)
  end

  @doc false
  @impl true
  @spec atomic(Ash.Changeset.t(), keyword(), Context.t()) ::
          {:ok, Ash.Changeset.t()}
  def atomic(changeset, opts, context), do: {:ok, change(changeset, opts, context)}

  defp revoke_sessions(user, opts) do
    # The installed log_out_everywhere add-on does not enable bulk notifications.
    # Use its native token action with notifications so LiveViews disconnect too.
    Token
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
