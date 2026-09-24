defmodule Firmowid.Ash.Invoicing.Services.PdfAugmentations.InternalNote do
  @moduledoc """
  Adds an internal-note page to an existing invoice PDF.

  The note page is always inserted after the first page so duplex printing puts
  the note on the back of page one.
  """

  alias Firmowid.Ash.Invoicing.Services.PdfUtils
  alias FirmowidWeb.Infrastructure.Utilities.PdfHelpers
  alias FirmowidWeb.Invoicing.Components.Print

  @doc """
  Inserts the internal-note page after the first page when requested.
  """
  @spec maybe_insert(binary(), binary() | nil, boolean()) :: {:ok, binary()} | {:error, term()}
  def maybe_insert(pdf_binary, _internal_note, false), do: {:ok, pdf_binary}

  def maybe_insert(pdf_binary, internal_note, true) when internal_note in [nil, ""] do
    {:ok, pdf_binary}
  end

  def maybe_insert(pdf_binary, internal_note, true) when is_binary(internal_note) do
    footer_logo_data_uri = PdfHelpers.file_to_data_uri(footer_logo_path())

    note_html =
      PdfHelpers.render_pdf_html(
        Print,
        :internal_note_page,
        %{
          internal_note: internal_note,
          footer_logo_data_uri: footer_logo_data_uri
        },
        page_margins: %{top: 32, bottom: 32, left: 32, right: 32}
      )

    with {:ok, note_pdf} <- PdfUtils.render_html_to_pdf(note_html, scale: 1.25) do
      PdfUtils.insert_page_after_first(pdf_binary, note_pdf)
    end
  end

  defp footer_logo_path do
    Path.join(:code.priv_dir(:firmowid), "static/images/invoice_firmowid_logo.png")
  end
end
