defmodule Firmowid.Ash.Invoicing.Services.GotenbergClient do
  @moduledoc "Small, non-retrying boundary for Gotenberg's Chromium HTML-to-PDF API."

  @doc """
  Converts an HTML document string into a PDF binary.

  ## Options

    * `:scale` - page rendering zoom factor (default `1.0`)
    * `:paper_width` / `:paper_height` - paper size, inches (default A4 `8.27` x `11.7`)
    * `:margin_top` / `:margin_bottom` / `:margin_left` / `:margin_right` - margins,
      inches (default `"0"`)
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

  defp form_fields(html_content, opts) do
    required = [
      files: {html_content, filename: "index.html", content_type: "text/html"},
      paperWidth: to_string(Keyword.get(opts, :paper_width, "8.27")),
      paperHeight: to_string(Keyword.get(opts, :paper_height, "11.7")),
      marginTop: to_string(Keyword.get(opts, :margin_top, "0")),
      marginBottom: to_string(Keyword.get(opts, :margin_bottom, "0")),
      marginLeft: to_string(Keyword.get(opts, :margin_left, "0")),
      marginRight: to_string(Keyword.get(opts, :margin_right, "0")),
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

    required ++ optional
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
