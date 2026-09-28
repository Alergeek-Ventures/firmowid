defmodule Firmowid.Ash.Invoicing.Services.GotenbergClient do
  @moduledoc """
  Small, non-retrying boundary for Gotenberg's Chromium HTML-to-PDF API.

  Also exposes the liveness probe backing the public `/health` endpoint, so
  reachability is verified on every health request rather than once at boot.
  """

  @health_receive_timeout 2_000

  @doc """
  Converts an HTML document string into a PDF binary.

  ## Options

    * `:scale` - page rendering zoom factor (default `1.0`)
    * `:paper_width` / `:paper_height` - paper size, inches (default A4 `8.27` x `11.7`)
    * `:header_html` - complete HTML document used as the repeating page header
      (sent as `header.html`; keep its height below the CSS `@page` top inset)
    * `:footer_html` - complete HTML document used as the repeating page footer
      (sent as `footer.html`; keep its height below the CSS `@page` bottom inset)
    * `:print_background` - include background graphics (default `true`)
    * `:emulated_media_type` - `"print"` (default) or `"screen"`
    * `:prefer_css_page_size` - use CSS `@page` size instead of API params
    * `:wait_delay` - e.g. `"1s"`, fixed wait before rendering
    * `:wait_for_expression` - JS expression; rendering starts when it returns true
    * `:wait_for_selector` - CSS selector; rendering starts when it appears in the DOM
    * `:trace` - custom request id sent as `Gotenberg-Trace`
  """
  @spec convert_html(binary(), keyword()) :: {:ok, binary()} | {:error, term()}
  def convert_html(html_content, opts \\ []) when is_binary(html_content) do
    config = Application.get_env(:firmowid, :gotenberg, [])

    req =
      Req.new(
        base_url: Keyword.fetch!(config, :base_url),
        receive_timeout: Keyword.get(config, :receive_timeout, 120_000),
        retry: false
      )

    case Req.post(req,
           url: "/forms/chromium/convert/html",
           form_multipart: form_fields(html_content, opts),
           headers: request_headers(opts)
         ) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status}} -> {:error, {:gotenberg_status, status}}
      {:error, reason} -> {:error, {:gotenberg_transport, reason}}
    end
  end

  @doc """
  Probes Gotenberg's `/health` endpoint.
  """
  @spec health(keyword()) ::
          :ok | {:error, :unconfigured | {:unhealthy, non_neg_integer()} | {:unreachable, term()}}
  def health(opts \\ []) do
    config = Application.get_env(:firmowid, :gotenberg, [])

    with {:ok, base_url} <- validated_base_url(Keyword.get(config, :base_url)) do
      url = health_url(base_url)
      request = health_request(url, config, opts)

      case Req.get(request) do
        {:ok, %Req.Response{status: status}} when status in 200..299 -> :ok
        {:ok, %Req.Response{status: status}} -> {:error, {:unhealthy, status}}
        {:error, reason} -> {:error, {:unreachable, reason}}
      end
    end
  end

  defp validated_base_url(base_url) when is_binary(base_url) do
    case URI.parse(base_url) do
      %URI{scheme: scheme, host: host}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        {:ok, base_url}

      _ ->
        {:error, :unconfigured}
    end
  end

  defp validated_base_url(_base_url), do: {:error, :unconfigured}

  defp health_url(base_url), do: String.trim_trailing(base_url, "/") <> "/health"

  defp health_request(url, config, opts) do
    [
      url: url,
      receive_timeout: Keyword.get(opts, :receive_timeout, @health_receive_timeout),
      retry: false
    ] ++ Keyword.take(config, [:plug])
  end

  defp form_fields(html_content, opts) do
    files =
      [{html_content, filename: "index.html", content_type: "text/html"}] ++ chrome_files(opts)

    file_fields = Enum.map(files, &{:files, &1})

    required = [
      paperWidth: to_string(Keyword.get(opts, :paper_width, "8.27")),
      paperHeight: to_string(Keyword.get(opts, :paper_height, "11.7")),
      scale: to_string(Keyword.get(opts, :scale, 1.0)),
      printBackground: to_string(Keyword.get(opts, :print_background, true))
    ]

    optional =
      [
        emulatedMediaType: Keyword.get(opts, :emulated_media_type),
        preferCssPageSize: prefer_css_page_size(opts),
        waitDelay: Keyword.get(opts, :wait_delay),
        waitForExpression: Keyword.get(opts, :wait_for_expression),
        waitForSelector: Keyword.get(opts, :wait_for_selector)
      ]
      |> Enum.reject(&is_nil(elem(&1, 1)))
      |> Enum.map(fn {name, value} -> {name, to_string(value)} end)

    file_fields ++ required ++ optional
  end

  # Gotenberg renders `header.html` / `footer.html` on every page. They travel
  # as extra `files` parts; Req preserves duplicate `:files` keys in order.
  defp chrome_files(opts) do
    Enum.flat_map([header_html: "header.html", footer_html: "footer.html"], fn {key, filename} ->
      case Keyword.get(opts, key) do
        nil -> []
        html -> [{html, filename: filename, content_type: "text/html"}]
      end
    end)
  end

  defp prefer_css_page_size(opts) do
    case Keyword.get(opts, :prefer_css_page_size) do
      nil -> nil
      value -> to_string(value)
    end
  end

  defp request_headers(opts) do
    case Keyword.get(opts, :trace) do
      nil -> []
      trace -> [{"Gotenberg-Trace", trace}]
    end
  end
end
