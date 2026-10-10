defmodule Firmowid.Ash.Core do
  @moduledoc """
  Core domain — identity and authentication.

  Owns the User, Organization, OrganizationInvite, Token, and UserIdentity resources.
  Authentication flows (password, Google OAuth, confirmation, password reset)
  are handled by `ash_authentication` on the User resource.

  Organization is fully writable with create, update, and destroy actions.
  OrganizationInvite handles invite creation, consumption, and expiry.
  """
  use Ash.Domain, extensions: [AshPhoenix, AshAi]

  alias Ash.Error.Query.NotFound
  alias Firmowid.Ash.Analysis.TagDefinition
  alias Firmowid.Ash.Assistant.Session, as: AssistantSession
  alias Firmowid.Ash.Billing.Snapshot
  alias Firmowid.Ash.Core.OauthAuthorizationCode
  alias Firmowid.Ash.Core.OauthConsent
  alias Firmowid.Ash.Core.OauthRefreshToken
  alias Firmowid.Ash.Core.Organization
  alias Firmowid.Ash.Core.OrganizationCleanup
  alias Firmowid.Ash.Core.OrganizationExternalCleanup
  alias Firmowid.Ash.Core.User
  alias Firmowid.Ash.Finances.Requisition
  alias Firmowid.Ash.Invoicing.KsefInvoiceDigest
  alias Firmowid.Ash.Invoicing.KsefInvoiceDigestItem
  alias Firmowid.Ash.Invoicing.SalesInvoiceEmailDelivery
  alias Firmowid.Ash.Payroll.UserEmploymentContract
  alias Firmowid.Ash.Payroll.UserSalary
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor
  alias Firmowid.Ash.Timetracker.LeaveRequest
  alias Firmowid.Ash.Timetracker.Project
  alias Firmowid.Ash.Timetracker.Session

  tools do
    tool :update_profile, User, :update_current_profile,
      description: "Update the authenticated user's profile information"

    tool :get_shared_birthday, User, :get_shared_birthday,
      description: "Returns the authenticated user's shared birthday (nil if not shared)"
  end

  resources do
    resource Organization do
      define :get_organization, action: :read, get_by: [:id]
      define :get_organization_by_nickname, action: :read, get_by: [:inbound_email_nickname]
      define :create_organization, action: :create
      define :update_organization, action: :update
      define :update_basic_info, action: :update_basic_info
      define :update_organization_billing_plan, action: :update_billing_plan
      define :update_organization_avatar, action: :update_avatar
      define :add_sender_email, action: :add_sender_email
      define :remove_sender_email, action: :remove_sender_email
      define :regenerate_nickname, action: :regenerate_nickname
      define :list_organizations, action: :list
    end

    resource User do
      define :register_with_password, action: :register_with_password
      define :get_user, action: :read, get_by: [:id]
      define :get_user_by_email, action: :read, get_by: [:email]
      define :list_users, action: :list
      define :get_org_user, action: :get_org_user
      define :update_profile, action: :update_profile
      define :change_email, action: :change_email
      define :update_current_profile, action: :update_current_profile
      define :get_shared_birthday, action: :get_shared_birthday
      define :update_role, action: :update_role
      define :archive_user, action: :archive
      define :unarchive_user, action: :unarchive
      define :set_organization, action: :set_organization
      define :clear_organization, action: :clear_organization
      define :update_user_avatar, action: :update_avatar
      define :unlink_google_account, action: :unlink_google
      define :change_password, action: :change_password
    end

    resource Firmowid.Ash.Core.Token

    resource Firmowid.Ash.Core.UserIdentity do
      define :read_user_identity_for_strategy,
        action: :read_for_user_and_strategy,
        args: [:user_id, :strategy]
    end

    resource Firmowid.Ash.Core.OrganizationInvite do
      define :list_invites, action: :read
      define :create_invite, action: :create
      define :get_invite, action: :read, get_by: [:id]
      define :read_invite_by_code, action: :read_by_code
      define :consume_invite, action: :consume
      define :destroy_invite, action: :destroy
    end

    resource Firmowid.Ash.Core.OauthClient
    resource OauthAuthorizationCode
    resource OauthRefreshToken
    resource OauthConsent
  end

  authorization do
    authorize :by_default
  end

  @transaction_resources [
    User,
    Organization,
    AssistantSession,
    Session,
    Snapshot,
    KsefInvoiceDigestItem,
    KsefInvoiceDigest,
    UserSalary,
    UserEmploymentContract,
    LeaveRequest,
    SalesInvoiceEmailDelivery,
    Project,
    TagDefinition,
    OauthAuthorizationCode,
    OauthConsent,
    OauthRefreshToken
  ]

  @doc """
  Destroys a user inside a single explicit Ash transaction.

  If the user owns an organization, best-effort remote cleanup happens after
  authorization and before the local transaction. Organization cleanup and the
  final user destroy share that transaction. Local failures roll it back and
  are reported for manual follow-up when remote cleanup was attempted.
  """
  @spec destroy_user(User.t(), Keyword.t()) :: :ok | {:error, term()}
  def destroy_user(%User{} = user, opts \\ []) do
    opts = ensure_actor(opts, user)

    with :ok <- authorize_destroy(user, opts),
         {:ok, organization} <- owned_organization(user, opts),
         :ok <- maybe_prepare_organization_deletion(organization, opts) do
      result = transact(fn -> destroy_user_in_transaction(user, opts) end)
      report_local_failure(result, organization, "owner_account_delete")
      result
    end
  end

  @doc """
  Destroys an organization after authorized, best-effort remote cleanup.

  Remote failures are reported but do not prevent the local transaction. Local
  failures roll back database changes and are reported for manual follow-up.
  """
  @spec destroy_organization(Organization.t(), Keyword.t()) :: :ok | {:error, term()}
  def destroy_organization(%Organization{} = organization, opts \\ []) do
    with :ok <- prepare_organization_deletion(organization, opts) do
      result = transact(fn -> destroy_organization_in_transaction(organization, opts) end)
      report_local_failure(result, organization, "organization_delete")
      result
    end
  end

  defp report_local_failure({:error, reason}, %Organization{id: id}, step),
    do: OrganizationExternalCleanup.report_local_failure(id, step, reason)

  defp report_local_failure(_result, _organization, _step), do: :ok

  defp transact(fun) do
    case Ash.transact(@transaction_resources, fun) do
      {:ok, :ok} -> :ok
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Runs user-destruction flow inside an existing transaction context.

  This function is public so transaction wrappers and integration tests can
  execute the same deletion logic when they already control transaction scope.
  Prefer `destroy_user/2` in regular application code.
  """
  @spec destroy_user_in_transaction(User.t(), Keyword.t()) :: :ok | {:error, term()}
  def destroy_user_in_transaction(%User{} = user, opts \\ []) do
    opts = ensure_actor(opts, user)

    with :ok <- authorize_destroy(user, opts),
         :ok <- maybe_destroy_owned_organization_in_transaction(user, opts),
         :ok <- OrganizationCleanup.remove_account_oauth_dependents(account_cleanup_scope(user)) do
      User.destroy(user, opts)
    end
  end

  @doc """
  Runs organization-destruction flow inside an existing transaction context.

  It deletes dependent projects and tag definitions, clears organization
  assignment for users, and then destroys the organization.
  Prefer `destroy_organization/2` in regular application code.
  """
  @spec destroy_organization_in_transaction(Organization.t(), Keyword.t()) ::
          :ok | {:error, term()}
  def destroy_organization_in_transaction(%Organization{} = organization, opts \\ []) do
    case authorize_destroy(organization, opts) do
      :ok ->
        scope = organization_cleanup_scope(organization)

        with :ok <- OrganizationCleanup.remove_dependents(scope),
             :ok <- OrganizationCleanup.detach_users(scope) do
          Organization.destroy(organization, opts)
        end

      {:error, error} ->
        {:error, error}
    end
  end

  defp maybe_destroy_owned_organization_in_transaction(user, opts) do
    case owned_organization(user, opts) do
      {:ok, %Organization{} = organization} ->
        destroy_organization_in_transaction(organization, opts)

      {:ok, nil} ->
        :ok

      {:error, error} ->
        {:error, error}
    end
  end

  defp organization_cleanup_scope(%Organization{id: id}) do
    %Scope{actor: %SystemActor{org_id: id, role: :organization_cleanup}, tenant: id}
  end

  defp account_cleanup_scope(%User{id: id, organization_id: organization_id}) do
    %Scope{
      actor: %SystemActor{org_id: organization_id, user_id: id, role: :account_cleanup},
      tenant: organization_id
    }
  end

  defp authorize_destroy(record, opts) do
    actor = actor_from_opts(opts)

    case Ash.can({record, :destroy}, actor,
           scope: %Scope{actor: actor, tenant: organization_id_for(record)},
           return_forbidden_error?: true
         ) do
      {:ok, true} -> :ok
      {:ok, false, error} -> {:error, error}
      {:ok, false} -> {:error, :forbidden}
      {:error, error} -> {:error, error}
      _ -> {:error, :forbidden}
    end
  end

  defp organization_id_for(%Organization{id: id}), do: id
  defp organization_id_for(%User{organization_id: id}), do: id

  defp owned_organization(%User{organization_id: nil}, _opts), do: {:ok, nil}

  defp owned_organization(%User{id: id, organization_id: organization_id}, opts) do
    case get_organization(organization_id, opts) do
      {:ok, %Organization{owner_id: ^id} = organization} -> {:ok, organization}
      {:ok, _} -> {:ok, nil}
      {:error, %NotFound{}} -> {:ok, nil}
      {:error, error} -> {:error, error}
    end
  end

  defp maybe_prepare_organization_deletion(nil, _opts), do: :ok

  defp maybe_prepare_organization_deletion(organization, opts), do: prepare_organization_deletion(organization, opts)

  defp prepare_organization_deletion(organization, opts) do
    case authorize_destroy(organization, opts) do
      :ok ->
        scope = organization_cleanup_scope(organization)

        case requisition_ids(scope) do
          {:ok, requisitions} -> OrganizationExternalCleanup.run(organization.id, requisitions)
          {:error, error} -> {:error, error}
        end

      {:error, error} ->
        {:error, error}
    end
  end

  defp requisition_ids(scope) do
    case Requisition.list(%{remote_deleted?: false}, scope: scope, query: [select: [:id]]) do
      {:ok, requisitions} when is_list(requisitions) ->
        if Enum.all?(requisitions, &is_binary(&1.id)) do
          {:ok, Enum.map(requisitions, & &1.id)}
        else
          {:error, :invalid_cleanup_requisition_id}
        end

      {:ok, _invalid_result} ->
        {:error, :invalid_cleanup_requisitions}

      {:error, error} ->
        {:error, error}
    end
  end

  defp ensure_actor(opts, actor) do
    if Keyword.has_key?(opts, :scope) or Keyword.has_key?(opts, :actor) do
      opts
    else
      Keyword.put(opts, :actor, actor)
    end
  end

  defp actor_from_opts(opts) do
    case Keyword.get(opts, :scope) do
      %Scope{actor: actor} -> actor
      _ -> Keyword.get(opts, :actor)
    end
  end
end
