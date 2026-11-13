defmodule FirmowidWeb.Infrastructure.Plugs.ContentSecurityPolicyReport do
  @moduledoc """
  Receives browsers' Content Security Policy violation reports and logs each as one line.

  Browsers post them to our own origin rather than to a third party, so the visitor's
  address and full URLs stay here. The plug runs in the endpoint before `Plug.Parsers`
  and the session: a report carries no cookies or CSRF token, and its body is read here
  with a small limit. It accepts both formats, `application/csp-report` (`report-uri`)
  and `application/reports+json` (`report-to`). The log line keeps only the directive,
  origins, the document path and a line number: no query strings, IP or identifiers,
  and no token a path carries (see `Firmowid.Sentry.scrub_sensitive_route/1`).
  Anyone can post here, so a value that is not a plain directive or URL is not logged,
  and one request logs a bounded number of lines. Reports about browser extensions'
  own code are dropped without a line.
  """

  @behaviour Plug

  import Plug.Conn

  require Logger

  @path "/csp-report"
  # A browser sends the reports it queued for the origin in one request.
  @max_body_bytes 256_000
  @max_reports 100

  @doc "Returns the same-origin path the policy sends its reports to."
  @spec path() :: String.t()
  def path, do: @path

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%Plug.Conn{method: "POST", request_path: @path} = conn, _opts) do
    case read_body(conn, length: @max_body_bytes) do
      {:ok, body, conn} -> conn |> send_resp(receive_reports(body), "") |> halt()
      {:more, _partial, conn} -> conn |> send_resp(:request_entity_too_large, "") |> halt()
    end
  end

  def call(conn, _opts), do: conn

  defp receive_reports(body) do
    case Jason.decode(body) do
      # `report-uri` sends one report per request.
      {:ok, %{"csp-report" => %{} = report}} ->
        log(
          report["effective-directive"] || report["violated-directive"],
          report["blocked-uri"],
          report["document-uri"],
          report["source-file"],
          report["line-number"]
        )

        :no_content

      # `report-to` batches reports of every type the page subscribed to.
      {:ok, reports} when is_list(reports) ->
        for %{"type" => "csp-violation", "body" => %{} = report} <-
              Enum.take(reports, @max_reports) do
          log(
            report["effectiveDirective"],
            report["blockedURL"],
            report["documentURL"],
            report["sourceFile"],
            report["lineNumber"]
          )
        end

        :no_content

      _invalid ->
        :bad_request
    end
  end

  defp log(directive, blocked, document, source, line) do
    blocked = origin(blocked)
    source = origin_and_path(source)

    if directive?(directive) and not extension?(blocked) and not extension?(source) do
      Logger.warning("Content Security Policy violation",
        csp_directive: directive,
        csp_blocked: blocked,
        csp_document: document_path(document),
        csp_source: source,
        csp_line: if(is_integer(line), do: line)
      )
    end
  end

  # Older browsers send the directive with its sources ("script-src 'self'"); those reports
  # are dropped with every other value that is not a bare directive name.
  defp directive?(value), do: is_binary(value) and Regex.match?(~r/\A[a-z-]{1,40}\z/, value)

  # A URL becomes its origin; `data:` and `blob:` URLs their scheme. Keywords such as
  # `inline` and `eval` stay, any other text is dropped so it cannot smuggle a query.
  defp origin(value) when is_binary(value) do
    case URI.parse(value) do
      %URI{scheme: scheme, host: host, port: port}
      when is_binary(scheme) and host not in [nil, ""] ->
        plain(URI.to_string(%URI{scheme: scheme, host: host, port: port}))

      %URI{scheme: scheme} when is_binary(scheme) ->
        plain(scheme)

      _keyword ->
        if Regex.match?(~r/\A[a-z-]{1,40}\z/, value), do: value
    end
  end

  defp origin(_value), do: nil

  defp origin_and_path(value) when is_binary(value) do
    case URI.parse(value) do
      %URI{scheme: scheme, host: host, port: port, path: path}
      when is_binary(scheme) and host not in [nil, ""] ->
        plain(URI.to_string(%URI{scheme: scheme, host: host, port: port, path: scrub_path(path)}))

      _other ->
        origin(value)
    end
  end

  defp origin_and_path(_value), do: nil

  defp document_path(value) when is_binary(value) do
    case URI.parse(value) do
      %URI{scheme: scheme, host: host, path: path}
      when scheme in ["http", "https"] and host not in [nil, ""] ->
        plain(scrub_path(path))

      _other ->
        nil
    end
  end

  defp document_path(_value), do: nil

  defp scrub_path(nil), do: nil

  # Decoded first, as the router matches a percent-encoded path too. A record's id says
  # nothing about what the policy blocked, so it goes as well.
  defp scrub_path(path) do
    path
    |> URI.decode()
    |> Firmowid.Sentry.scrub_sensitive_route()
    |> String.replace(~r/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i, "[ID]")
  end

  # Printable ASCII without spaces, of a sane length: nothing that could start a new log
  # line or pose as another key.
  defp plain(value) when is_binary(value), do: if(Regex.match?(~r/\A[\x21-\x7E]{1,300}\z/, value), do: value)

  defp plain(nil), do: nil

  # moz-extension:, chrome-extension:, safari-web-extension: and the like (Firefox may
  # report the bare scheme without a colon), and Safari's mask for an extension's URL.
  defp extension?(value) when is_binary(value) do
    scheme = value |> String.split(":", parts: 2) |> hd()
    String.ends_with?(scheme, "extension") or scheme == "webkit-masked-url"
  end

  defp extension?(nil), do: false
end
