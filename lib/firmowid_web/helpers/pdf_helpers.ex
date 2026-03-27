defmodule FirmowidWeb.PdfHelpers do
  @moduledoc """
  Helpers for PDF generation with ChromicPDF.
  Handles asset embedding and HTML rendering.
  """

  require Logger

  @doc """
  Converts a remote image URL to a data URI.

  Fetches the image from the URL, detects MIME type, and returns
  a base64-encoded data URI suitable for embedding in HTML.

  Returns nil if the URL is nil or if fetching fails.

  ## Examples

      iex> url_to_data_uri("https://example.com/logo.png")
      "data:image/png;base64,iVBORw0KGgo..."

      iex> url_to_data_uri(nil)
      nil
  """
  def url_to_data_uri(nil), do: nil

  def url_to_data_uri(url) when is_binary(url) do
    case Req.get(url) do
      {:ok, %{status: 200, body: body, headers: headers}} ->
        mime_type = get_mime_type(headers, url)
        encoded = Base.encode64(body)
        "data:#{mime_type};base64,#{encoded}"

      {:ok, %{status: status}} ->
        Logger.warning("Failed to fetch asset for PDF: #{url} (HTTP #{status})")
        nil

      {:error, reason} ->
        Logger.error("Error fetching asset for PDF: #{url}, reason: #{inspect(reason)}")
        nil
    end
  end

  @doc """
  Converts a local file to a data URI.

  Reads the file from the filesystem and returns a base64-encoded data URI.

  Returns nil if the path is nil or if reading fails.

  ## Examples

      iex> file_to_data_uri("priv/static/images/logo.png")
      "data:image/png;base64,iVBORw0KGgo..."

      iex> file_to_data_uri(nil)
      nil
  """
  def file_to_data_uri(nil), do: nil

  # sobelow_skip ["Traversal.FileModule"]
  # Callers pass hardcoded priv/static paths or nil, not user input.
  def file_to_data_uri(path) when is_binary(path) do
    case File.read(path) do
      {:ok, body} ->
        mime_type = guess_mime_type_from_url(path)
        encoded = Base.encode64(body)
        "data:#{mime_type};base64,#{encoded}"

      {:error, reason} ->
        Logger.error("Error reading file for PDF: #{path}, reason: #{inspect(reason)}")
        nil
    end
  end

  defp get_mime_type(headers, url) do
    # Req returns headers as a map with list values
    # e.g., %{"content-type" => ["application/octet-stream"]}
    case Map.get(headers, "content-type") do
      [mime_type | _] ->
        mime_type |> String.split(";") |> List.first()

      nil ->
        # Fallback: guess from file extension
        guess_mime_type_from_url(url)
    end
  end

  defp guess_mime_type_from_url(url) do
    cond do
      String.ends_with?(url, ".png") -> "image/png"
      String.ends_with?(url, ".jpg") or String.ends_with?(url, ".jpeg") -> "image/jpeg"
      String.ends_with?(url, ".gif") -> "image/gif"
      String.ends_with?(url, ".svg") -> "image/svg+xml"
      String.ends_with?(url, ".webp") -> "image/webp"
      true -> "application/octet-stream"
    end
  end

  @doc """
  Renders a Phoenix template to an HTML string for PDF generation.

  Wraps the content in a complete HTML document with inlined CSS for ChromicPDF.

  ## Examples

      iex> render_pdf_html(FirmowidWeb.PdfHTML, :sales_invoice, assigns)
      "<!DOCTYPE html><html>...</html>"
  """
  def render_pdf_html(view_module, template, assigns) do
    # Render template to string using Phoenix.Template
    # Template name needs to be a string with format
    template_name = to_string(template)

    content =
      Phoenix.Template.render_to_string(
        view_module,
        template_name,
        "html",
        assigns
      )

    # Inline CSS by reading the compiled app.css file
    # CSS includes @font-face rule for Lexend font installed in container
    css_content = get_app_css()

    """
    <!DOCTYPE html>
    <html>
      <head>
        <meta charset="utf-8" />
        <style>
          #{css_content}
        </style>
      </head>
      <body>
        #{content}
      </body>
    </html>
    """
  end

  # sobelow_skip ["Traversal.FileModule"]
  # Reads a hardcoded path (priv/static/assets/app.css), not user input.
  defp get_app_css do
    css_path = Path.join(:code.priv_dir(:firmowid), "static/assets/app.css")

    case File.read(css_path) do
      {:ok, css} ->
        # Replace Google Fonts import with @font-face pointing to container's local font.
        # The Google Fonts @import won't work when Chrome can't make external requests.
        # Tailwind v4 minifies `@import url("...")` to `@import "..."`, so we match both forms.
        String.replace(
          css,
          ~r/@import\s+(?:url\()?"https:\/\/fonts\.googleapis\.com\/css2\?family=Lexend[^"]+"\)?;/,
          """
          @font-face {
            font-family: 'Lexend';
            font-style: normal;
            font-weight: 100 900;
            src: local('Lexend'), url('file:///usr/share/fonts/truetype/lexend/Lexend.ttf') format('truetype');
          }
          """
        )

      {:error, reason} ->
        Logger.warning("Could not read app.css for PDF generation: #{inspect(reason)}. PDF may lack styles.")

        ""
    end
  end
end
