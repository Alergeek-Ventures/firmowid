defmodule FirmowidWeb.Infrastructure.UserAuth do
  @moduledoc """
  Authentication plugs for browser and API pipelines.

  These plugs work with `conn.assigns.current_user` already populated by
  `load_from_session` / `load_from_bearer` plugs from AshAuthentication.
  """
  use FirmowidWeb, :verified_routes

  import Phoenix.Controller
  import Plug.Conn

  alias AshAuthentication.Phoenix.Controller, as: AuthController
  alias Firmowid.Ash.Scope
  alias FirmowidWeb.Organization.Utilities.Navigation, as: OrganizationNavigation

  @expired_subscription_path "/abonament-wygasl"
  @disabled_account_path "/konto-wylaczone"

  @type blocked_page :: :disabled_account | :expired_subscription | nil
  @type blocked_access :: %{
          page: blocked_page(),
          path: String.t() | nil,
          message: String.t() | nil
        }

  @doc """
  Builds a Scope, loads avatars for user and organization.

  Shared by both the Plug pipeline (`require_authenticated_user_with_organization`)
  and the LiveView hook (`RequireOrganization.on_mount`).
  """
  @spec load_scope_and_avatars(map()) :: {map(), map(), Scope.t()}
  def load_scope_and_avatars(user) do
    scope = Scope.new!(user, user.organization_id)
    user = Ash.load!(user, [:organization, avatar_blob: [:url]], scope: scope)
    org = Ash.load!(user.organization, [avatar_blob: [:url]], scope: scope)
    {user, org, scope}
  end

  @type billing_block_status :: :owner | :member | nil

  @doc """
  Plug: restores or refreshes the LiveView socket ID from the validated session token.

  The existing connection is returned when the topic is already current, avoiding
  an unnecessary session-cookie write on every browser request.
  """
  @spec restore_live_socket_id(Plug.Conn.t(), term()) :: Plug.Conn.t()
  def restore_live_socket_id(conn, _opts) do
    case {conn.assigns[:current_user], get_session(conn, :user_token)} do
      {user, token} when not is_nil(user) and is_binary(token) ->
        updated_conn = AuthController.set_live_socket_id(conn, token)

        if get_session(updated_conn, :live_socket_id) == get_session(conn, :live_socket_id) do
          conn
        else
          updated_conn
        end

      _ ->
        conn
    end
  end

  @doc """
  Plug: Requires authenticated user with organization (browser).
  """
  def require_authenticated_user_with_organization(conn, _opts) do
    cond do
      is_nil(conn.assigns[:current_user]) ->
        conn
        |> maybe_store_return_to()
        |> LiveToast.put_toast(:notice, "Musisz się zalogować.")
        |> redirect(to: ~p"/zaloguj")
        |> halt()

      is_nil(conn.assigns[:current_user].organization_id) ->
        conn
        |> maybe_store_return_to()
        |> LiveToast.put_toast(:notice, "Aby przejść dalej, przypisz sobie organizację.")
        |> redirect(to: OrganizationNavigation.onboarding_path())
        |> halt()

      true ->
        {user, org, ash_scope} = load_scope_and_avatars(conn.assigns[:current_user])

        case blocked_access(user, org) do
          %{path: nil} ->
            conn
            |> assign(:current_user, user)
            |> assign(:current_org, org)
            |> assign(:ash_scope, ash_scope)

          %{path: path, message: message} ->
            conn
            |> LiveToast.put_toast(:error, message)
            |> redirect(to: path)
            |> halt()
        end
    end
  end

  @doc """
  Plug: Requires authenticated user without organization (onboarding).
  """
  def require_authenticated_user_without_organization(conn, _opts) do
    user = conn.assigns[:current_user]

    cond do
      is_nil(user) ->
        conn
        |> maybe_store_return_to()
        |> LiveToast.put_toast(:notice, "Musisz się zalogować, żeby wejść na tę stronę.")
        |> redirect(to: ~p"/zaloguj")
        |> halt()

      is_nil(user.organization_id) ->
        conn

      true ->
        conn
        |> maybe_store_return_to()
        |> LiveToast.put_toast(
          :notice,
          "Ta strona jest dostępna tylko przed wyborem organizacji."
        )
        |> redirect(to: signed_in_path(conn))
        |> halt()
    end
  end

  @doc """
  Plug: Requires superuser role.
  """
  def require_superuser(conn, _opts) do
    if conn.assigns.current_user.system_role == :superuser do
      conn
    else
      conn
      |> redirect(to: ~p"/")
      |> halt()
    end
  end

  @doc """
  Plug: Redirects authenticated users away from guest pages.
  """
  def redirect_if_user_is_authenticated(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
      |> redirect(
        to:
          if(is_nil(conn.assigns[:current_user].organization_id),
            do: OrganizationNavigation.onboarding_path(),
            else: signed_in_path(conn)
          )
      )
      |> halt()
    else
      conn
    end
  end

  @doc """
  Stores the return URL for post-login redirect.
  """
  def maybe_store_return_to(%{method: "GET"} = conn) do
    put_session(conn, :return_to, current_path(conn))
  end

  def maybe_store_return_to(conn), do: conn

  @doc """
  Returns the default signed-in path.
  """
  @spec signed_in_path(Plug.Conn.t()) :: String.t()
  def signed_in_path(conn), do: signed_in_path_for_user(conn.assigns[:current_user])

  @doc """
  Returns the default signed-in path for a user.

  Users with invoicing permissions (`:invoicing`, `:accountant`, `:admin`) are
  redirected to invoicing hub, while other users land on time tracking.

  When the user belongs to an organization, the organization relationship is
  loaded on demand so blocked-account routing stays consistent across browser
  plugs, LiveView hooks, and auth controller redirects.
  """
  @spec signed_in_path_for_user(map() | nil) :: String.t()
  def signed_in_path_for_user(%{archived_at: archived_at}) when not is_nil(archived_at), do: ~p"/konto-wylaczone"

  def signed_in_path_for_user(user) do
    user = maybe_load_organization_for_signed_in_path(user)

    case user do
      %{organization: organization} = loaded_user
      when not is_nil(organization) and not is_struct(organization, Ash.NotLoaded) ->
        case blocked_access(loaded_user, organization) do
          %{path: nil} -> signed_in_path_for_active_user(loaded_user)
          %{path: path} -> path
        end

      %{role: role} when role in [:invoicing, :accountant, :admin] ->
        ~p"/fakturowanie"

      _user ->
        ~p"/czasosledz"
    end
  end

  @spec archived_user?(map()) :: boolean()
  def archived_user?(%{archived_at: archived_at}), do: not is_nil(archived_at)
  def archived_user?(_), do: false

  @doc """
  Returns the blocked-access decision for the user in an organization context.
  """
  @spec blocked_access(map() | nil, map() | nil) :: blocked_access()
  def blocked_access(nil, _org), do: %{page: nil, path: nil, message: nil}

  def blocked_access(user, org) do
    case blocked_page_for(user, org) do
      :disabled_account ->
        %{
          page: :disabled_account,
          path: @disabled_account_path,
          message: "To konto zostało wyłączone."
        }

      :expired_subscription ->
        %{
          page: :expired_subscription,
          path: @expired_subscription_path,
          message: "Abonament organizacji wygasł."
        }

      nil ->
        %{page: nil, path: nil, message: nil}
    end
  end

  @spec blocked_path_for_user(map(), map()) :: String.t() | nil
  def blocked_path_for_user(user, org), do: blocked_access(user, org).path

  @doc """
  Returns whether a blocked page should render or redirect away.
  """
  @spec blocked_page_action(:disabled_account | :expired_subscription, map() | nil, map() | nil) ::
          :ok | {:redirect, String.t()}
  def blocked_page_action(:disabled_account, nil, _org), do: :ok
  def blocked_page_action(_page, nil, _org), do: {:redirect, ~p"/"}

  def blocked_page_action(page, user, org) do
    case blocked_access(user, org) do
      %{page: ^page} -> :ok
      _ -> {:redirect, signed_in_path_for_user(user)}
    end
  end

  @spec blocked_owner?(map(), map()) :: boolean()
  def blocked_owner?(user, org), do: billing_block_status(user, org) == :owner

  @spec blocked_member?(map(), map()) :: boolean()
  def blocked_member?(user, org), do: billing_block_status(user, org) == :member

  @spec billing_block_status(map(), map()) :: billing_block_status()
  # Deliberate temporary coupling:
  # pre-Stripe we still manage subscription lifecycle outside the app, so until
  # we introduce a first-class subscription status, `:no_plan` intentionally
  # serves both as the zero-plan catalog entry and as the signal that
  # organization access should be blocked here.
  #
  # This is not accidental. Keep access checks aligned with this convention and
  # only split the concepts once lifecycle state moves into application data.
  def billing_block_status(user, org) do
    cond do
      superuser?(user) -> nil
      Map.get(org, :billing_plan) != :no_plan -> nil
      Map.get(user, :id) == Map.get(org, :owner_id) -> :owner
      true -> :member
    end
  end

  @spec superuser?(map()) :: boolean()
  def superuser?(%{system_role: :superuser}), do: true
  def superuser?(_), do: false

  defp blocked_page_for(user, org) do
    cond do
      archived_user?(user) -> :disabled_account
      superuser?(user) -> nil
      is_nil(org) -> nil
      true -> blocked_page_for_billing_status(billing_block_status(user, org))
    end
  end

  defp blocked_page_for_billing_status(:owner), do: :expired_subscription
  defp blocked_page_for_billing_status(:member), do: :disabled_account
  defp blocked_page_for_billing_status(nil), do: nil

  defp maybe_load_organization_for_signed_in_path(nil), do: nil
  defp maybe_load_organization_for_signed_in_path(%{organization_id: nil} = user), do: user

  defp maybe_load_organization_for_signed_in_path(%{organization: organization} = user)
       when not is_nil(organization) and not is_struct(organization, Ash.NotLoaded), do: user

  defp maybe_load_organization_for_signed_in_path(%{organization_id: organization_id} = user)
       when not is_nil(organization_id) do
    scope = Scope.new!(user, organization_id)
    Ash.load!(user, [:organization], scope: scope)
  end

  defp maybe_load_organization_for_signed_in_path(user), do: user

  defp signed_in_path_for_active_user(%{role: role}) when role in [:invoicing, :accountant, :admin], do: ~p"/fakturowanie"

  defp signed_in_path_for_active_user(_user), do: ~p"/czasosledz"
end
