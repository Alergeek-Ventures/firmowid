defmodule FirmowidWeb.Infrastructure.UserAuth do
  @moduledoc """
  Authentication plugs for browser and API pipelines.

  These plugs work with `conn.assigns.current_user` already populated by
  `load_from_session` / `load_from_bearer` plugs from AshAuthentication.
  """
  use FirmowidWeb, :verified_routes

  import Phoenix.Controller
  import Plug.Conn

  alias Firmowid.Ash.Scope
  alias FirmowidWeb.Infrastructure.Controllers.Fallback

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
        |> redirect(to: ~p"/organization")
        |> halt()

      true ->
        user = conn.assigns[:current_user]

        # Load avatar on user and organization
        user =
          Ash.load!(user, [:organization, avatar_blob: [:url]],
            tenant: user.organization_id,
            authorize?: false,
            actor: %{}
          )

        org =
          Ash.load!(user.organization, [avatar_blob: [:url]],
            tenant: user.organization_id,
            authorize?: false,
            actor: %{}
          )

        ash_scope = %Scope{actor: user, tenant: user.organization_id}

        conn
        |> assign(:current_user, user)
        |> assign(:current_org, org)
        |> assign(:ash_scope, ash_scope)
    end
  end

  @doc """
  Plug: Requires authenticated user with organization (API).
  """
  def require_authenticated_user_with_organization_api(conn, _opts) do
    user = conn.assigns[:current_user]

    if not is_nil(user) and not is_nil(user.organization_id) do
      ash_scope = %Scope{actor: user, tenant: user.organization_id}

      conn
      |> assign(:current_org, user.organization)
      |> assign(:ash_scope, ash_scope)
    else
      conn
      |> Fallback.call({:error, :unauthorized})
      |> halt()
    end
  end

  @doc """
  Plug: Requires authenticated user without organization (onboarding).
  """
  def require_authenticated_user_without_organization(conn, _opts) do
    user = conn.assigns[:current_user]

    if not is_nil(user) and is_nil(user.organization_id) do
      conn
    else
      conn
      |> maybe_store_return_to()
      |> LiveToast.put_toast(:notice, "Musisz się zalogować, żeby wejść na tę stronę.")
      |> redirect(to: ~p"/organization")
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
            do: ~p"/organization",
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
  def signed_in_path(_conn), do: ~p"/czasosledz"
end
