defmodule Firmowid.Ash.Core do
  @moduledoc """
  Core domain — identity and authentication.

  Owns the User, Organization, OrganizationInvite, Token, and UserIdentity resources.
  Authentication flows (password, Google OAuth, confirmation, password reset)
  are handled by `ash_authentication` on the User resource.

  Organization is fully writable with create, update, and destroy actions.
  OrganizationInvite handles invite creation, consumption, and expiry.
  """
  use Ash.Domain, extensions: [AshPhoenix]

  alias Firmowid.Ash.Analysis.TagDefinition
  alias Firmowid.Ash.Core.Organization
  alias Firmowid.Ash.Core.User
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.Timetracker.Project

  require Ash.Query

  resources do
    resource Organization do
      define :get_organization, action: :read, get_by: [:id]
      define :get_organization_by_nickname, action: :read, get_by: [:inbound_email_nickname]
      define :create_organization, action: :create
      define :update_organization, action: :update
      define :update_basic_info, action: :update_basic_info
      define :update_correspondence, action: :update_correspondence
      define :update_organization_avatar, action: :update_avatar
      define :add_sender_email, action: :add_sender_email
      define :remove_sender_email, action: :remove_sender_email
      define :regenerate_nickname, action: :regenerate_nickname
    end

    resource User do
      define :register_with_password, action: :register_with_password
      define :get_user, action: :read, get_by: [:id]
      define :get_user_by_email, action: :read, get_by: [:email]
      define :list_users, action: :list
      define :get_org_user, action: :get_org_user
      define :update_profile, action: :update_profile
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
  end

  authorization do
    authorize :by_default
  end

  @transaction_resources [User, Organization, Project, TagDefinition]

  @doc """
  Destroys a user inside a single explicit Ash transaction.

  If the user owns an organization, the organization cleanup and the final user
  destroy are executed in the same database transaction.
  """
  @spec destroy_user(User.t(), Keyword.t()) :: :ok | {:error, term()}
  def destroy_user(%User{} = user, opts \\ []) do
    case Ash.transact(@transaction_resources, fn -> destroy_user_in_transaction(user, opts) end) do
      {:ok, :ok} -> :ok
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Destroys an organization inside a single explicit Ash transaction.
  """
  @spec destroy_organization(Organization.t(), Keyword.t()) :: :ok | {:error, term()}
  def destroy_organization(%Organization{} = organization, opts \\ []) do
    case Ash.transact(@transaction_resources, fn ->
           destroy_organization_in_transaction(organization, opts)
         end) do
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
    with :ok <- maybe_destroy_owned_organization_in_transaction(user, opts) do
      Ash.destroy(user, Keyword.put(opts, :action, :destroy))
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
    org_opts = organization_opts(opts, organization.id)

    with {:ok, projects} <- Ash.read(Project, org_opts),
         :ok <- destroy_all(projects, Keyword.put(org_opts, :action, :destroy)),
         {:ok, tag_definitions} <- Ash.read(TagDefinition, org_opts),
         :ok <-
           destroy_all(tag_definitions, Keyword.put(org_opts, :action, :destroy_tag_definition)),
         {:ok, organization_users} <- organization_users(organization.id, org_opts),
         :ok <- clear_organization_for_all(organization_users, org_opts) do
      Ash.destroy(organization, Keyword.put(opts, :action, :destroy))
    end
  end

  defp maybe_destroy_owned_organization_in_transaction(%User{organization_id: nil}, _opts), do: :ok

  defp maybe_destroy_owned_organization_in_transaction(%User{id: user_id, organization_id: organization_id} = user, opts) do
    case Ash.get(Organization, organization_id, ensure_actor(opts, user)) do
      {:ok, %Organization{owner_id: ^user_id} = organization} ->
        destroy_organization_in_transaction(organization, opts)

      {:ok, _organization} ->
        :ok

      {:error, %Ash.Error.Query.NotFound{}} ->
        :ok

      {:error, error} ->
        {:error, error}
    end
  end

  defp organization_users(organization_id, opts) do
    User
    |> Ash.Query.filter(organization_id: organization_id)
    |> Ash.read(opts)
  end

  defp clear_organization_for_all(users, opts) do
    Enum.reduce_while(users, :ok, fn user, :ok ->
      case Ash.update(user, %{}, Keyword.put(opts, :action, :clear_organization)) do
        {:ok, _user} -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp destroy_all(records, opts) do
    Enum.reduce_while(records, :ok, fn record, :ok ->
      case Ash.destroy(record, opts) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp organization_opts(opts, organization_id) do
    [scope: %Scope{actor: actor_from_opts(opts), tenant: organization_id}]
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
