defmodule FirmowidWeb.UserAuth do
  use FirmowidWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias FirmowidWeb.FallbackController
  alias Firmowid.Accounts

  # Make the remember me cookie valid for 60 days.
  # If you want bump or reduce this value, also change
  # the token expiry itself in UserToken.
  @max_age 60 * 60 * 24 * 60
  @remember_me_cookie "_firmowid_web_user_remember_me"
  @remember_me_options [sign: true, max_age: @max_age, same_site: "Lax"]

  @doc """
  Logs the user in.

  It renews the session ID and clears the whole session
  to avoid fixation attacks. See the renew_session
  function to customize this behaviour.

  It also sets a `:live_socket_id` key in the session,
  so LiveView sessions are identified and automatically
  disconnected on log out. The line can be safely removed
  if you are not using LiveView.
  """
  def log_in_user(conn, user, params \\ %{}) do
    token = Accounts.generate_user_session_token(user)
    user_return_to = get_session(conn, :user_return_to)

    conn
    |> renew_session()
    |> put_token_in_session(token)
    |> maybe_write_remember_me_cookie(token, params)
    |> redirect(to: user_return_to || signed_in_path(conn))
  end

  defp maybe_write_remember_me_cookie(conn, token, %{"remember_me" => "true"}) do
    put_resp_cookie(conn, @remember_me_cookie, token, @remember_me_options)
  end

  defp maybe_write_remember_me_cookie(conn, _token, _params) do
    conn
  end

  # This function renews the session ID and erases the whole
  # session to avoid fixation attacks. If there is any data
  # in the session you may want to preserve after log in/log out,
  # you must explicitly fetch the session data before clearing
  # and then immediately set it after clearing, for example:
  #
  #     defp renew_session(conn) do
  #       preferred_locale = get_session(conn, :preferred_locale)
  #
  #       conn
  #       |> configure_session(renew: true)
  #       |> clear_session()
  #       |> put_session(:preferred_locale, preferred_locale)
  #     end
  #
  defp renew_session(conn) do
    delete_csrf_token()

    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  @doc """
  Logs the user out.

  It clears all session data for safety. See renew_session.
  """
  def log_out_user(conn) do
    user_token = get_session(conn, :user_token)
    user_token && Accounts.delete_user_session_token(user_token)

    if live_socket_id = get_session(conn, :live_socket_id) do
      FirmowidWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    conn
    |> renew_session()
    |> delete_resp_cookie(@remember_me_cookie)
    |> LiveToast.put_toast(:notice, "Wylogowano.")
    |> redirect(to: ~p"/zaloguj")
  end

  @doc """
  Authenticates the user by looking into the session
  and remember me token.
  """
  def fetch_current_user(conn, _opts) do
    {user_token, conn} = ensure_user_token(conn)
    user = user_token && Accounts.get_user_by_session_token(user_token)
    assign(conn, :current_user, user)
  end

  def fetch_api_user(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, decoded_token} <- Base.url_decode64(token),
         user <-
           Accounts.get_user_by_session_token(decoded_token) do
      conn |> assign(:current_user, user)
    else
      _ ->
        conn |> assign(:current_user, nil)
    end
  end

  defp ensure_user_token(conn) do
    if token = get_session(conn, :user_token) do
      {token, conn}
    else
      conn = fetch_cookies(conn, signed: [@remember_me_cookie])

      if token = conn.cookies[@remember_me_cookie] do
        {token, put_token_in_session(conn, token)}
      else
        {nil, conn}
      end
    end
  end

  @doc """
  Handles mounting and authenticating the current_user in LiveViews.

  ## `on_mount` arguments

    * `:mount_current_user` - Assigns current_user
      to socket assigns based on user_token, or nil if
      there's no user_token or no matching user.

    * `:ensure_authenticated` - Authenticates the user from the session,
      and assigns the current_user to socket assigns based
      on user_token.
      Redirects to login page if there's no logged user.

    * `:redirect_if_user_is_authenticated` - Authenticates the user from the session.
      Redirects to signed_in_path if there's a logged user.

  ## Examples

  Use the `on_mount` lifecycle macro in LiveViews to mount or authenticate
  the current_user:

      defmodule FirmowidWeb.PageLive do
        use FirmowidWeb, :live_view

        on_mount {FirmowidWeb.UserAuth, :mount_current_user}
        ...
      end

  Or use the `live_session` of your router to invoke the on_mount callback:

      live_session :authenticated, on_mount: [{FirmowidWeb.UserAuth, :ensure_authenticated}] do
        live "/profile", ProfileLive, :index
      end
  """
  def on_mount(:mount_current_user, _params, session, socket) do
    {:cont, mount_current_user(socket, session)}
  end

  def on_mount(:ensure_authenticated_without_organization, _params, session, socket) do
    socket = mount_current_user(socket, session)

    if not is_nil(socket.assigns.current_user) and
         is_nil(socket.assigns.current_user.organization_id) do
      {:cont, socket}
    else
      if is_nil(socket.assigns.current_user.organization_id) do
        socket =
          socket
          |> LiveToast.put_toast(
            :notice,
            "Aby przejść dalej, przypisz sobie organizację."
          )
          |> Phoenix.LiveView.redirect(to: ~p"/organization")

        {:halt, socket}
      else
        socket =
          socket
          |> Phoenix.LiveView.redirect(to: ~p"/")

        {:halt, socket}
      end
    end
  end

  def on_mount(:ensure_authenticated_with_organization, _params, session, socket) do
    socket = mount_current_user(socket, session)

    if not is_nil(socket.assigns.current_user) and
         not is_nil(socket.assigns.current_user.organization_id) do
      Firmowid.Repo.put_org_id(socket.assigns.current_user.organization_id)

      {:cont,
       socket |> Phoenix.Component.assign(:current_org, socket.assigns.current_user.organization)}
    else
      socket =
        socket
        |> LiveToast.put_toast(
          :notice,
          "Musisz się zalogować."
        )
        |> Phoenix.LiveView.redirect(to: ~p"/zaloguj")

      {:halt, socket}
    end
  end

  def on_mount(:redirect_if_user_is_authenticated, _params, session, socket) do
    socket = mount_current_user(socket, session)

    if socket.assigns.current_user do
      if is_nil(socket.assigns.current_user.organization_id) do
        {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/organization")}
      else
        {:halt, Phoenix.LiveView.redirect(socket, to: signed_in_path(socket))}
      end
    else
      {:cont, socket}
    end
  end

  defp mount_current_user(socket, session) do
    Phoenix.Component.assign_new(socket, :current_user, fn ->
      if user_token = session["user_token"] do
        Accounts.get_user_by_session_token(user_token)
      end
    end)
  end

  @doc """
  Used for routes that require the user to not be authenticated.
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
  Used for routes that require the user to be authenticated.

  If you want to enforce the user email is confirmed before
  they use the application at all, here would be a good place.
  """
  def require_authenticated_user_with_organization(conn, _opts) do
    if not is_nil(conn.assigns[:current_user]) do
      if not is_nil(conn.assigns[:current_user].organization_id) do
        Firmowid.Repo.put_org_id(conn.assigns[:current_user].organization_id)

        conn |> assign(:current_org, conn.assigns[:current_user].organization)
      else
        conn
        |> maybe_store_return_to()
        |> LiveToast.put_toast(
          :notice,
          "Aby przejść dalej, przypisz sobie organizację."
        )
        |> redirect(to: ~p"/organization")
        |> halt()
      end
    else
      conn
      |> maybe_store_return_to()
      |> LiveToast.put_toast(
        :notice,
        "Musisz się zalogować."
      )
      |> redirect(to: ~p"/zaloguj")
      |> halt()
    end
  end

  def require_authenticated_user_with_organization_api(conn, _opts) do
    if not is_nil(conn.assigns[:current_user]) and
         not is_nil(conn.assigns[:current_user].organization_id) do
      Firmowid.Repo.put_org_id(conn.assigns[:current_user].organization_id)

      conn |> assign(:current_org, conn.assigns[:current_user].organization)
    else
      conn
      |> FallbackController.call({:error, :unauthorized})
      |> halt()
    end
  end

  def redirect_employees_to_timetracker(conn, _opts) do
    if conn.assigns[:current_user].role == :employee do
      conn
      |> redirect(to: ~p"/czasosledz")
      |> halt()
    else
      conn
    end
  end

  def require_superuser(conn, _opts) do
    if conn.assigns.current_user.system_role == :superuser do
      conn
    else
      conn
      |> redirect(to: ~p"/")
      |> halt()
    end
  end

  def require_authenticated_user_without_organization(conn, _opts) do
    if not is_nil(conn.assigns[:current_user]) and
         is_nil(conn.assigns[:current_user].organization_id) do
      conn
    else
      conn
      |> maybe_store_return_to()
      |> LiveToast.put_toast(
        :notice,
        "Musisz się zalogować, żeby wejść na tę stronę."
      )
      |> redirect(to: ~p"/organization")
      |> halt()
    end
  end

  defp put_token_in_session(conn, token) do
    conn
    |> put_session(:user_token, token)
    |> put_session(:live_socket_id, "users_sessions:#{Base.url_encode64(token)}")
  end

  defp maybe_store_return_to(%{method: "GET"} = conn) do
    put_session(conn, :user_return_to, current_path(conn))
  end

  defp maybe_store_return_to(conn), do: conn

  defp signed_in_path(_conn), do: ~p"/"
end
