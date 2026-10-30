defmodule FirmowidWeb.Core.Endpoint do
  # Endpoint integration must install Sentry's PlugCapture plug directly.
  # credo:disable-for-next-line Checks.RejectDirectSentrySdk
  use Elixir.Sentry.PlugCapture
  use Phoenix.Endpoint, otp_app: :firmowid

  # The endpoint must configure the SDK plug with the application's scrubbers.
  # credo:disable-for-next-line Checks.RejectDirectSentrySdk
  alias Elixir.Sentry, as: SentrySDK
  alias Firmowid.Sentry
  alias FirmowidWeb.Core.RequestLogMetadata
  alias Phoenix.LiveView.Socket

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  @session_options [
    store: :cookie,
    key: "_firmowid_key",
    signing_salt: "3lt8Vcq/",
    same_site: "Lax"
  ]

  socket "/live", Socket,
    websocket: [connect_info: [:peer_data, :uri, :user_agent, session: @session_options]],
    longpoll: [connect_info: [:peer_data, :uri, :user_agent, session: @session_options]]

  # sobelow_skip ["Config.CSWH"]
  # False positive: Sobelow cannot inspect the MFA callback's origin validation.
  # It permits only the exact app origin or ChatGPT's HTTPS sandbox on port 443.
  # No browser cookies are loaded; mounts and events validate an OAuth-derived,
  # widget-bound capability and its current actor/tenant scope server-side.
  socket "/mcp/live", Socket,
    websocket: [
      connect_info: [:uri],
      check_origin: {FirmowidMcp.Session, :allowed_origin?, []}
    ],
    longpoll: false

  # Public font assets are also loaded by the cross-origin ChatGPT sandbox.
  plug Plug.Static,
    at: "/fonts",
    from: {:firmowid, "priv/static/fonts"},
    headers: [{"access-control-allow-origin", "*"}]

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phx.digest
  # when deploying your static files in production.
  plug Plug.Static,
    at: "/",
    from: :firmowid,
    gzip: false,
    only: FirmowidWeb.static_paths()

  if Code.ensure_loaded?(Tidewave) do
    # Remote development access is protected by the dashboard's private tailnet.
    # Keep Tidewave's origin validation and never enable remote access outside dev.
    plug Tidewave,
      allow_remote_access: Application.compile_env(:firmowid, :tidewave_remote_access, false)
  end

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :firmowid
  end

  plug Phoenix.LiveDashboard.RequestLogger,
    param_key: "request_logger",
    cookie_key: "request_logger"

  plug Plug.RequestId
  plug RequestLogMetadata

  plug Plug.Telemetry,
    event_prefix: [:phoenix, :endpoint],
    log: {RequestLogMetadata, :log_level, []}

  plug FirmowidWeb.Infrastructure.Plugs.TelemetryProxy

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    body_reader: {FirmowidWeb.Core.CacheBodyReader, :read_body, []},
    json_decoder: Phoenix.json_library()

  # Parsed form and cookie presence must be observed before CSRF rejects login.
  # Keep request logging before Telemetry and reuse the existing capture boundary.
  plug :password_login_diagnostics

  plug SentrySDK.PlugContext,
    body_scrubber: {Sentry, :scrub_body},
    header_scrubber: {Sentry, :scrub_headers},
    cookie_scrubber: {Sentry, :scrub_cookies},
    url_scrubber: {Sentry, :scrub_url}

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug FirmowidWeb.Core.Router

  defp password_login_diagnostics(conn, _opts), do: Sentry.put_password_login_context(conn, url(), @session_options[:key])
end
