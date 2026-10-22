defmodule Firmowid.Ash.Core do
  @moduledoc """
  Core domain — identity and authentication.

  Owns the User, Member, Organization, OrganizationInvite, Token, and UserIdentity resources.
  Authentication flows (password, Google OAuth, confirmation, password reset)
  are handled by `ash_authentication` on the User resource.

  Organization is fully writable with create, update, and destroy actions.
  OrganizationInvite handles invite creation, consumption, and expiry.
  """
  use Ash.Domain, extensions: [AshPhoenix, AshAi]

  alias Firmowid.Ash.Analysis.TagDefinition
  alias Firmowid.Ash.Billing.Snapshot
  alias Firmowid.Ash.Core.Member
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
      load: [:member],
      annotations: [
        title: "Update profile",
        read_only_hint: false,
        destructive_hint: true,
        open_world_hint: false
      ],
      description:
        "Update the authenticated user's own profile: name, phone, Slack URL, bank account number, birthday " <>
          "and its visibility, residence and correspondence addresses. Pass only the fields to change."

    tool :get_shared_birthday, User, :get_shared_birthday,
      annotations: [
        title: "Get shared birthday",
        read_only_hint: true,
        destructive_hint: false,
        open_world_hint: false
      ],
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
      define :change_email, action: :change_email
      define :update_current_profile, action: :update_current_profile
      define :get_shared_birthday, action: :get_shared_birthday
      define :leave_organization, action: :leave_organization, args: [:organization_id]
      define :set_organization, action: :set_organization
      define :unlink_google_account, action: :unlink_google
      define :change_password, action: :change_password
    end

    resource Member do
      define :update_member_role, action: :update_role
      define :update_member_profile, action: :update_profile
      define :update_member_avatar, action: :update_avatar
      define :archive_member, action: :archive
      define :unarchive_member, action: :unarchive
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

    resource OauthAuthorizationCode do
      define :get_oauth_authorization_code, action: :read, get_by: [:id]
    end

    resource OauthRefreshToken do
      define :get_oauth_refresh_token_by_hash, action: :read, get_by: [:token_hash]
    end

    resource OauthConsent
  end

  authorization do
    authorize :by_default
  end

  @transaction_resources [
    User,
    Member,
    Organization,
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
  Lists the user's active members, most recently updated first, with their
  organizations.

  Authorizing the read as the user would need the role it loads, so a system actor
  limited to this user's members reads them.
  """
  @spec list_active_members(User.t()) :: [Member.t()]
  def list_active_members(%User{id: id}) do
    actor = %SystemActor{org_id: nil, role: :actor_member_loader, user_id: id}
    Member.list_active!(id, actor: actor, load: [:organization])
  end

  @doc """
  Lists the active members the user can work as: those of organizations with a
  billing plan (see the User `:access_block` calculation), or all for a superuser.
  """
  @spec list_usable_members(User.t()) :: [Member.t()]
  def list_usable_members(%User{} = user) do
    user
    |> list_active_members()
    |> Enum.reject(&(user.system_role != :superuser and &1.organization.billing_plan == :no_plan))
  end

  @doc """
  Loads the member the user works as, whose organization is the tenant and which
  policies read the actor's role from.

  It is the user's usable member in `organization_id` (the organization selected
  in the session) or, when there is none, the most recently updated usable
  member (see `list_usable_members/1`). A user without one gets `nil`.
  """
  @spec load_member(User.t(), binary() | nil) :: User.t()
  def load_member(%User{} = user, organization_id \\ nil),
    do: select_member(user, list_usable_members(user), organization_id)

  @doc """
  Puts on the user the member from `members` (see `list_usable_members/1`) that
  `load_member/2` would load.
  """
  @spec select_member(User.t(), [Member.t()], binary() | nil) :: User.t()
  def select_member(%User{} = user, members, organization_id) do
    %{
      user
      | member: Enum.find(members, List.first(members), &(&1.organization_id == organization_id))
    }
  end

  @doc """
  Destroys a user inside a single explicit Ash transaction.

  For each organization the user owns, best-effort remote cleanup happens after
  authorization and before the local transaction. Organization cleanup and the
  final user destroy share that transaction. Local failures roll it back and
  are reported for manual follow-up when remote cleanup was attempted.
  """
  @spec destroy_user(User.t(), Keyword.t()) :: :ok | {:error, term()}
  def destroy_user(%User{} = user, opts \\ []) do
    opts = ensure_actor(opts, user)
    owned = owned_organizations(user, opts)

    with :ok <- authorize_destroy(user, opts),
         :ok <-
           each_ok(owned, fn {organization, owner_opts} ->
             prepare_organization_deletion(organization, owner_opts)
           end) do
      result = transact(fn -> destroy_user_in_transaction(user, opts) end)

      Enum.each(owned, fn {organization, _opts} ->
        report_local_failure(result, organization, "owner_account_delete")
      end)

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

    cleanup_scope = account_cleanup_scope(user)

    with :ok <- authorize_destroy(user, opts),
         :ok <-
           each_ok(owned_organizations(user, opts), fn {organization, owner_opts} ->
             destroy_organization_in_transaction(organization, owner_opts)
           end),
         :ok <- OrganizationCleanup.remove_account_oauth_dependents(cleanup_scope) do
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

  defp each_ok(items, fun) do
    Enum.reduce_while(items, :ok, fn item, :ok ->
      case fun.(item) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp organization_cleanup_scope(%Organization{id: id}) do
    %Scope{actor: %SystemActor{org_id: id, role: :organization_cleanup}, tenant: id}
  end

  defp account_cleanup_scope(%User{id: id}) do
    %Scope{actor: %SystemActor{org_id: nil, user_id: id, role: :account_cleanup}}
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
  defp organization_id_for(%User{}), do: nil

  @doc """
  Lists the organizations the user owns, which closing the account deletes.
  """
  @spec list_owned_organizations(User.t()) :: [Organization.t()]
  def list_owned_organizations(%User{} = user), do: Enum.map(owned_members(user), & &1.organization)

  # Each organization the user owns, with the options its deletion is authorized
  # with: the user acts as their member there.
  defp owned_organizations(%User{} = user, opts) do
    for member <- owned_members(user), do: {member.organization, owner_opts(opts, member)}
  end

  defp owned_members(%User{id: id} = user) do
    Enum.filter(list_active_members(user), &(&1.organization.owner_id == id))
  end

  defp owner_opts(opts, %Member{user_id: user_id} = member) do
    case actor_from_opts(opts) do
      %User{id: ^user_id} = actor ->
        opts |> Keyword.delete(:scope) |> Keyword.put(:actor, %{actor | member: member})

      _actor ->
        opts
    end
  end

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
