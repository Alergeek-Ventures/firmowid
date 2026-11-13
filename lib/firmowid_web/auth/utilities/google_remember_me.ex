defmodule FirmowidWeb.Auth.Utilities.GoogleRememberMe do
  @moduledoc """
  Carries the sign-in page's "Remember me" box through the round trip to Google.

  While the box is ticked, the page shows the Google button that links to the
  strategy with `remember_me=true` (see `FirmowidWeb.Auth.Views.Login`). Starting
  the sign-in keeps that choice in the session, replacing the choice of an
  abandoned attempt. Google's callback takes it out of the session, whatever the
  outcome, and passes it to the `:register_with_google` action as Ash context: the
  action issues the remember-me token and the strategy's dispatcher sets the
  cookie, as for a password sign-in. Install before the auth routes; only the
  Google paths are inspected.
  """

  @behaviour Plug

  import Ash.PlugHelpers, only: [update_context: 2]
  import Plug.Conn, only: [delete_session: 2, get_session: 2, put_session: 3]

  @session_key "google_remember_me"

  @doc "Accepts the pipeline's keyword options without changing them."
  @impl true
  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @doc "Keeps the choice when the Google sign-in starts and hands it to the action on return."
  @impl true
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(%{path_info: ["auth", "user", "google"]} = conn, _opts) do
    case conn.query_params do
      %{"remember_me" => "true"} -> put_session(conn, @session_key, true)
      _params -> delete_session(conn, @session_key)
    end
  end

  def call(%{path_info: ["auth", "user", "google", "callback"]} = conn, _opts) do
    remember_me = get_session(conn, @session_key) == true

    conn
    |> delete_session(@session_key)
    |> update_context(&Map.put(&1 || %{}, :remember_me, remember_me))
  end

  def call(conn, _opts), do: conn
end
