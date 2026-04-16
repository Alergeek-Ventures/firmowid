defmodule Firmowid.Ash.Invoicing.Services.MonthDownloadEntries do
  @moduledoc """
  Builds deterministic batch-download ZIP entries for a selected month.

  This module encapsulates invoice selection rules for the monthly ZIP export,
  while keeping HTTP streaming concerns in the web controller.
  """

  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Scope

  require Ash.Query

  @type include_options :: %{
          required(:include_digital) => boolean(),
          required(:include_ksef) => boolean(),
          required(:include_photos) => boolean(),
          required(:include_sales) => boolean(),
          optional(:include_internal_note) => boolean()
        }

  @doc """
  Builds Packmatic entry descriptors for the provided month and include options.

  Returns a list of entries in the format expected by `Packmatic.build_stream/2`.
  """
  @spec build(Date.t(), include_options(), Scope.t(), binary(), binary()) :: [keyword()]
  def build(month, include_opts, %Scope{} = scope, session_cookie, endpoint_url) do
    date_range_from = Date.beginning_of_month(month)
    date_range_to = Date.end_of_month(month)
    ash_opts = [scope: scope]

    cost_invoices =
      CostInvoice
      |> Ash.Query.for_read(
        :read,
        %{
          date_from: date_range_from,
          date_to: date_range_to,
          date_field: :any
        },
        ash_opts
      )
      |> Ash.Query.filter(not is_nil(blob_id))
      |> Ash.Query.load([:effective_seller_display_name, blob: [:url]])
      |> Ash.read!(ash_opts)
      |> Enum.filter(&include_cost_invoice?(&1, include_opts))
      |> Enum.map(fn document ->
        file_name =
          clean_filename(
            "#{document.issue_date}_#{document.effective_seller_display_name}_#{String.slice(document.blob.blob_checksum, 0, 8)}"
          )

        cost_download_entry(document, include_opts, session_cookie, endpoint_url, file_name)
      end)

    sales_invoices =
      if include_opts.include_sales do
        %{date_from: date_range_from, date_to: date_range_to, date_field: :any}
        |> SalesInvoice.read!(Keyword.put(ash_opts, :load, [:buyer_display_name_label]))
        |> Enum.map(fn invoice ->
          file_name =
            clean_filename("#{invoice.invoice_number}_#{invoice.buyer_display_name_label}")

          query = URI.encode_query(include_internal_note: include_internal_note?(include_opts))
          download_path = "/sprzedazowe/#{invoice.id}/pobierz?#{query}"

          base_url = String.trim_trailing(endpoint_url, "/")

          [
            source: {:url, {"#{base_url}#{download_path}", [headers: [{"cookie", "_firmowid_key=#{session_cookie}"}]]}},
            path: "sprzedazowe/#{file_name}.pdf"
          ]
        end)
      else
        []
      end

    cost_invoices ++ sales_invoices
  end

  @doc """
  Sanitizes invoice-derived file names for zip paths.
  """
  @spec clean_filename(binary()) :: binary()
  def clean_filename(filename) do
    filename
    |> AnyAscii.transliterate()
    |> IO.iodata_to_binary()
    |> String.downcase()
    |> String.trim()
    |> String.replace(" ", "_")
    |> String.replace(".", "_")
    |> String.replace("/", "_")
  end

  @spec include_cost_invoice?(map(), include_options()) :: boolean()
  defp include_cost_invoice?(invoice, include_opts) do
    extension =
      invoice.blob.url
      |> String.split("?")
      |> hd()
      |> Path.extname()
      |> String.downcase()

    case extension do
      ".pdf" -> include_opts.include_digital
      ".xml" -> include_opts.include_ksef
      _image -> include_opts.include_photos
    end
  end

  defp cost_download_entry(document, include_opts, session_cookie, endpoint_url, file_name) do
    if pdf_downloadable?(document) do
      query = URI.encode_query(include_internal_note: include_internal_note?(include_opts))
      base_url = String.trim_trailing(endpoint_url, "/")

      [
        source:
          {:url,
           {"#{base_url}/kosztowe/#{document.id}/pobierz?#{query}",
            [headers: [{"cookie", "_firmowid_key=#{session_cookie}"}]]}},
        path: "kosztowe/#{file_name}.pdf"
      ]
    else
      blob_url = document.blob.url

      file_extension =
        blob_url
        |> String.split("?")
        |> hd()
        |> Path.extname()

      [
        source: {:url, blob_url},
        path: "kosztowe/#{file_name}#{file_extension}"
      ]
    end
  end

  defp pdf_downloadable?(%{ksef_number: ksef_number}) when not is_nil(ksef_number), do: true

  defp pdf_downloadable?(document) do
    extension =
      document.blob.url
      |> String.split("?")
      |> hd()
      |> Path.extname()
      |> String.downcase()

    extension == ".pdf"
  end

  defp include_internal_note?(include_opts), do: Map.get(include_opts, :include_internal_note, true)
end
