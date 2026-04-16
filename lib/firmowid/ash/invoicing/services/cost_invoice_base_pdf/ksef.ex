defmodule Firmowid.Ash.Invoicing.Services.CostInvoiceBasePdf.Ksef do
  @moduledoc """
  Generates the base PDF for KSeF-backed cost invoices.
  """

  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Invoicing.Services.PdfUtils
  alias Firmowid.Ash.Ksef

  @padding_style "<style>body { padding: 16px; }</style>"

  # sobelow_skip ["Traversal.FileModule"]
  # Hardcoded path to the KSeF XSL template in priv/static, not user input.
  @xsl_template_path Path.join(
                       :code.priv_dir(:firmowid),
                       "static/templates/kseffaktura_fa(3).xsl"
                     )

  @doc """
  Generates the base KSeF cost-invoice PDF.
  """
  @spec generate(CostInvoice.t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def generate(%CostInvoice{} = invoice, opts \\ []) do
    ash_scope = Keyword.get(opts, :scope)

    with {:ok, xml_content} <- load_xml_content(invoice, ash_scope),
         {:ok, xsl_content} <- load_xsl_content(),
         {:ok, qrcode_data_uri} <- qrcode_data_uri(invoice, ash_scope) do
      render_invoice_pdf(invoice, xml_content, xsl_content, qrcode_data_uri)
    end
  end

  defp load_xml_content(invoice, ash_scope) do
    invoice =
      invoice
      |> Invoicing.hydrate_invoice_with_fa3_blob()
      |> Ash.load!([blob: [:url]], scope: ash_scope)

    case Req.get(invoice.blob.url) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status}} -> {:error, {:xml_fetch_failed, status}}
      {:error, reason} -> {:error, {:xml_fetch_failed, reason}}
    end
  end

  defp load_xsl_content do
    case File.read(@xsl_template_path) do
      {:ok, xsl_content} -> {:ok, sanitize_xsl_fonts(xsl_content)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp sanitize_xsl_fonts(xsl_content) do
    xsl_content
    |> String.replace(
      ~s(<link href="https://fonts.googleapis.com/css?family=Open&#x2B;Sans" rel="stylesheet"/>),
      ""
    )
    |> String.replace(
      ~s(<link href="https://fonts.googleapis.com/css?family=Montserrat" rel="stylesheet"/>),
      ""
    )
  end

  defp qrcode_data_uri(invoice, ash_scope) do
    {:ok, png_binary} =
      invoice
      |> Ksef.invoice_url!(scope: ash_scope)
      |> QRCode.create()
      |> QRCode.render(:png)

    {:ok, "data:image/png;base64,#{Base.encode64(png_binary)}"}
  end

  defp render_invoice_pdf(invoice, xml_content, xsl_content, qrcode_data_uri) do
    with {:ok, transformed_html} <- PdfUtils.xslt_transform(xml_content, xsl_content) do
      html_content = build_invoice_html(invoice, transformed_html, qrcode_data_uri)
      PdfUtils.render_html_to_pdf(html_content, scale: 1.0)
    end
  end

  defp build_invoice_html(invoice, transformed_html, qrcode_data_uri) do
    sanitized_html =
      String.replace(transformed_html, ~r/<link[^>]*fonts\.googleapis\.com[^>]*\/?>/, "")

    qr_overlay = qr_code_overlay(qrcode_data_uri, invoice.ksef_number)

    String.replace(sanitized_html, "<body>", "<body>#{@padding_style}#{qr_overlay}", global: false)
  end

  defp qr_code_overlay(qrcode_data_uri, ksef_number) do
    """
    <div style="position:fixed;bottom:4px;right:4px;z-index:1000;width:120px;\
    background:white;padding:8px;border:1px solid rgba(0,0,0,0.12);\
    border-radius:12px;text-align:center;">\
    <div style="font-size:10px;font-weight:600;line-height:1.3;margin-bottom:6px;">\
    Sprawdź w KSeF</div>\
    <img src="#{qrcode_data_uri}" alt="KSeF QR" \
    style="width:96px;height:96px;margin:0 auto;display:block;"/>\
    <div style="font-size:10px;line-height:1.3;margin-top:6px;word-break:break-word;">\
    #{ksef_number}</div>\
    </div>
    """
  end
end
