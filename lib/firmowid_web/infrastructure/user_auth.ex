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

        conn
        |> assign(:current_user, user)
        |> assign(:current_org, org)
        |> assign(:ash_scope, ash_scope)
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
  """
  @spec signed_in_path_for_user(map() | nil) :: String.t()
  def signed_in_path_for_user(%{role: role}) when role in [:invoicing, :accountant, :admin], do: ~p"/fakturowanie"

  def signed_in_path_for_user(_user), do: ~p"/czasosledz"

  @spec superuser?(map()) :: boolean()
  def superuser?(%{system_role: :superuser}), do: true
  def superuser?(_), do: false
end
