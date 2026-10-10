defmodule FirmowidWeb.Core.Endpoint do
  # Endpoint integration must install Sentry's PlugCapture plug directly.
  # credo:disable-for-next-line Checks.RejectDirectSentrySdk
  use Elixir.Sentry.PlugCapture
  use Phoenix.Endpoint, otp_app: :firmowid

  # The endpoint must configure the SDK plug with the application's scrubbers.
  # credo:disable-for-next-line Checks.RejectDirectSentrySdk
  alias Elixir.Sentry, as: SentrySDK
  alias Firmowid.Sentry
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

  # The callback validates the exact app origin or ChatGPT's sandbox HTTPS domain.
  # No browser cookies are loaded: every mount requires an OAuth-derived capability.
  @mcp_websocket_options [
    connect_info: [:uri],
    check_origin: {FirmowidWeb.Mcp.Session, :allowed_origin?, []}
  ]
  socket "/mcp/live", Socket, websocket: @mcp_websocket_options, longpoll: false

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
  plug FirmowidWeb.Core.RequestLogMetadata
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug FirmowidWeb.Infrastructure.Plugs.TelemetryProxy

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    body_reader: {FirmowidWeb.Core.CacheBodyReader, :read_body, []},
    json_decoder: Phoenix.json_library()

  plug SentrySDK.PlugContext,
    body_scrubber: {Sentry, :scrub_body},
    header_scrubber: {Sentry, :scrub_headers},
    cookie_scrubber: {Sentry, :scrub_cookies},
    url_scrubber: {Sentry, :scrub_url}

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug FirmowidWeb.Core.Router
end
