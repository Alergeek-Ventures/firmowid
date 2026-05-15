defmodule FirmowidWeb.Invoicing.Utilities.MonthDownloadPackmatic do
  @moduledoc """
  Adapts monthly invoice-download descriptors into Packmatic ZIP entries.
  """

  alias Firmowid.Ash.Invoicing.Services.MonthDownloadEntries
  alias FirmowidWeb.Invoicing.Utilities.Navigation

  @doc """
  Builds Packmatic entries from monthly download descriptors.
  """
  @spec build_entries(
          [
            MonthDownloadEntries.download_descriptor()
          ],
          boolean(),
          String.t() | nil,
          String.t()
        ) :: [keyword()]
  def build_entries(descriptors, include_internal_note, session_cookie, endpoint_url)
      when is_list(descriptors) and is_boolean(include_internal_note) and is_binary(endpoint_url) do
    Enum.map(
      descriptors,
      &build_entry(&1, include_internal_note, session_cookie, endpoint_url)
    )
  end

  defp build_entry(
         %{source: {:generated_pdf, :sales, invoice_id}, path: path},
         include_internal_note,
         session_cookie,
         endpoint_url
       ) do
    build_authenticated_entry(
      Navigation.sales_invoice_pdf_download_path(invoice_id, include_internal_note),
      path,
      session_cookie,
      endpoint_url
    )
  end

  defp build_entry(
         %{source: {:generated_pdf, :cost, invoice_id}, path: path},
         include_internal_note,
         session_cookie,
         endpoint_url
       ) do
    build_authenticated_entry(
      Navigation.cost_invoice_pdf_download_path(invoice_id, include_internal_note),
      path,
      session_cookie,
      endpoint_url
    )
  end

  defp build_entry(%{source: {:remote_url, blob_url}, path: path}, _include_internal_note, _session_cookie, _endpoint_url) do
    [source: {:url, blob_url}, path: path]
  end

  defp build_authenticated_entry(download_path, path, session_cookie, endpoint_url) do
    base_url = String.trim_trailing(endpoint_url, "/")

    [
      source: {:url, {"#{base_url}#{download_path}", [headers: [{"cookie", "_firmowid_key=#{session_cookie}"}]]}},
      path: path
    ]
  end
end
