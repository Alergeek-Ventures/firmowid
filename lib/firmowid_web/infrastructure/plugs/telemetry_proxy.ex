defmodule FirmowidWeb.Infrastructure.Plugs.TelemetryProxy do
  @moduledoc """
  Relays browser telemetry through opaque same-origin paths.

  This plug runs before `Plug.Parsers`, and deliberately has a small, fixed set
  of upstream destinations. It never acts as a general-purpose proxy.
  """

  @behaviour Plug

  alias Plug.Conn

  @posthog_paths %{
    "/_x/19a4/" => "/i/v0/e/",
    "/_x/27bf/" => "/e/",
    "/_x/3d81/" => "/s/",
    "/_x/4c6e/" => "/flags/",
    "/_x/5ab2/" => "/array/",
    "/_x/6f93/" => "/static/"
  }
  @posthog_methods ~w(GET HEAD POST)
  @sentry_path "/_x/8e2f"
  @forwarded_headers ~w(accept content-type content-encoding)
  @response_headers ~w(content-type content-encoding)
  @posthog_host "i.alergeek.workers.dev"

  @impl Plug
  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @impl Plug
  @spec call(Conn.t(), keyword()) :: Conn.t()
  def call(conn, _opts) do
    cond do
      posthog_enabled?() and not is_nil(posthog_path(conn.request_path)) ->
        posthog(conn)

      sentry_enabled?() and conn.request_path in [@sentry_path, @sentry_path <> "/"] ->
        sentry(conn)

      true ->
        conn
    end
  end

  defp posthog(conn) do
    if conn.method in @posthog_methods do
      with {opaque, path} <- posthog_path(conn.request_path),
           true <- safe_suffix?(conn.request_path, opaque),
           {:ok, body, conn} <- maybe_read_body(conn, 1_000_000) do
        request(conn, "https://#{@posthog_host}#{path}", body)
      else
        false -> reject(conn, :bad_request)
        {:error, :too_large} -> reject(conn, :request_entity_too_large)
      end
    else
      reject_method(conn, @posthog_methods)
    end
  end

  defp sentry(conn) do
    cond do
      conn.query_string != "" ->
        reject(conn, :bad_request)

      conn.method != "POST" ->
        reject_method(conn, ["POST"])

      true ->
        with {:ok, url} <- sentry_url(Application.get_env(:sentry, :dsn)),
             {:ok, body, conn} <- maybe_read_body(conn, 10_000_000) do
          request(conn, url, body)
        else
          {:error, :too_large} -> reject(conn, :request_entity_too_large)
          _ -> reject(conn, :bad_gateway)
        end
    end
  end

  defp request(conn, url, body) do
    options = [
      method: method(conn.method),
      url: url <> query(conn),
      headers: forwarded_headers(conn.req_headers),
      raw: true,
      decode_body: false,
      redirect: false,
      retry: false,
      max_retries: 0
    ]

    options = if is_nil(body), do: options, else: Keyword.put(options, :body, body)

    case Req.request(options) do
      {:ok, response} ->
        conn = put_response_headers(conn, response.headers)
        send_response(conn, response.status, response.body)

      {:error, _reason} ->
        reject(conn, :bad_gateway)
    end
  end

  defp maybe_read_body(conn, _limit) when conn.method in ["GET", "HEAD"], do: {:ok, nil, conn}

  defp maybe_read_body(conn, limit) do
    case Conn.read_body(conn, length: limit + 1) do
      {:ok, body, conn} when byte_size(body) <= limit -> {:ok, body, conn}
      {:ok, _body, _conn} -> {:error, :too_large}
      {:more, _body, _conn} -> {:error, :too_large}
    end
  end

  defp posthog_path(path) do
    Enum.find_value(@posthog_paths, fn {opaque, original} ->
      if String.starts_with?(path, opaque),
        do: {opaque, original <> String.trim_leading(path, opaque)}
    end)
  end

  defp safe_suffix?(path, opaque) do
    suffix = String.trim_leading(path, opaque)

    suffix == "" or
      Regex.match?(
        ~r/^\/?[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)*(?:\/[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)*)*\/?$/,
        suffix
      )
  end

  defp sentry_url(dsn) when is_binary(dsn) do
    with %URI{
           scheme: "https",
           host: host,
           port: port,
           userinfo: userinfo,
           path: path,
           query: nil,
           fragment: nil
         } = uri <- URI.parse(dsn),
         true <- trusted_sentry_host?(host) and port in [nil, 443],
         true <- public_key?(userinfo),
         {:ok, prefix, project} <- project_path(path) do
      {:ok, "https://#{uri.host}#{prefix}/api/#{project}/envelope/"}
    else
      _ -> :error
    end
  end

  defp sentry_url(_), do: :error

  defp project_path(path) when is_binary(path) do
    segments = path |> String.trim_trailing("/") |> String.split("/", trim: true)

    case List.pop_at(segments, -1) do
      {project, prefix} when project != "" ->
        if Regex.match?(~r/^\d+$/, project) do
          {:ok, if(prefix == [], do: "", else: "/" <> Enum.join(prefix, "/")), project}
        else
          :error
        end

      _ ->
        :error
    end
  end

  defp project_path(_), do: :error

  defp public_key?(value), do: is_binary(value) and value |> String.split(":", parts: 2) |> hd() != ""

  defp trusted_sentry_host?(host), do: is_binary(host) and (host == "sentry.io" or String.ends_with?(host, ".sentry.io"))

  defp sentry_enabled?, do: not is_nil(Application.get_env(:sentry, :dsn))
  defp posthog_enabled?, do: Application.get_env(:posthog, :enable, false)
  defp query(%{query_string: ""}), do: ""
  defp query(%{query_string: query}), do: "?" <> query

  defp method("GET"), do: :get
  defp method("HEAD"), do: :head
  defp method("POST"), do: :post

  defp forwarded_headers(headers),
    do: Enum.filter(headers, fn {name, _} -> String.downcase(name) in @forwarded_headers end)

  defp put_response_headers(conn, headers),
    do:
      Enum.reduce(headers, conn, fn {name, values}, conn ->
        if String.downcase(name) in @response_headers,
          do: Conn.put_resp_header(conn, name, List.first(List.wrap(values))),
          else: conn
      end)

  # sobelow_skip ["XSS.SendResp"]
  # The body is opaque binary telemetry returned by the fixed HTTPS upstream;
  # it is not interpolated into HTML.
  defp send_response(conn, status, body), do: conn |> Conn.send_resp(status, body) |> Conn.halt()

  defp reject_method(conn, methods),
    do: conn |> Conn.put_resp_header("allow", Enum.join(methods, ", ")) |> reject(:method_not_allowed)

  defp reject(conn, status), do: conn |> Conn.send_resp(status, "") |> Conn.halt()
end
