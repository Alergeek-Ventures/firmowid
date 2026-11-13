defmodule FirmowidWeb.Infrastructure.Plugs.ContentSecurityPolicy do
  @moduledoc """
  Sends the Content Security Policy of browser pages with a fresh nonce per request.

  The nonce is assigned as `:csp_nonce`, so the root layout and the LiveDashboard
  and Oban dashboards can mark their inline scripts. The `:enforce?` setting of
  this module chooses between `content-security-policy` and the report-only header.
  While report-only, Phoenix's default `base-uri 'self'; frame-ancestors 'self'`
  policy from `put_secure_browser_headers` stays enforced; the full policy below
  repeats both directives, so enforcing it replaces that default without loss.

  Browsers send violation reports to `ContentSecurityPolicyReport`: those supporting the
  Reporting API through `report-to` and the `reporting-endpoints` header, the others
  through `report-uri`.
  """

  @behaviour Plug

  import Plug.Conn

  alias Firmowid.S3Client
  alias FirmowidWeb.Infrastructure.Plugs.ContentSecurityPolicyReport

  @enforce? Application.compile_env(:firmowid, [__MODULE__, :enforce?], false)

  @bank_logos "https://cdn-logos.gocardless.com https://storage.googleapis.com/gc-prd-institution_icons-production/"

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    nonce = 18 |> :crypto.strong_rand_bytes() |> Base.encode64()

    conn
    |> assign(:csp_nonce, nonce)
    |> put_resp_header(header(), policy(nonce))
    |> put_resp_header("reporting-endpoints", ~s(csp="#{ContentSecurityPolicyReport.path()}"))
  end

  defp header, do: if(@enforce?, do: "content-security-policy", else: "content-security-policy-report-only")

  # form-action is left out: the OAuth consent form redirects to each MCP client's own
  # redirect URI (any origin, including http://localhost), which form-action would block.
  defp policy(nonce) do
    storage = S3Client.browser_origin()

    Enum.join(
      [
        "default-src 'self'",
        "script-src 'self' 'nonce-#{nonce}'#{dev_sources(:script)}",
        # LiveView patches server-rendered style attributes with setAttribute, and the
        # KSeF XSLT preview's <style> runs in a srcdoc iframe, which inherits this policy
        # and cannot carry a nonce. That preview's official stylesheet also loads Google Fonts.
        "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com#{dev_sources(:style)}",
        # LiveDashboard embeds its icon font as a data: URL.
        "font-src 'self' data: https://fonts.gstatic.com",
        # Presigned storage URLs (invoice previews, logos) and bank logos from GoCardless.
        "img-src 'self' data: blob: #{storage} #{@bank_logos}",
        "connect-src 'self' #{storage}#{dev_sources(:connect)}",
        # PDF.js runs its worker from /assets; Sentry Replay and canvas-confetti start blob: workers.
        "worker-src 'self' blob:",
        "object-src 'none'",
        "base-uri 'self'",
        "frame-ancestors 'self'",
        "report-uri #{ContentSecurityPolicyReport.path()}",
        "report-to csp"
      ],
      "; "
    )
  end

  if Code.ensure_loaded?(LiveDebugger) do
    # LiveDebugger (development only) injects a script and a stylesheet served from its
    # own port and connects back to it over a websocket. Tidewave needs nothing here: it
    # rewrites an enforced policy itself (deps/tidewave/lib/tidewave.ex).
    defp dev_sources(kind) do
      config = Application.get_all_env(:live_debugger)
      host = config |> Keyword.fetch!(:ip) |> :inet.ntoa()
      port = Keyword.fetch!(config, :port)

      case kind do
        :connect -> " ws://#{host}:#{port}"
        _script_or_style -> " http://#{host}:#{port}"
      end
    end
  else
    defp dev_sources(_kind), do: ""
  end
end
