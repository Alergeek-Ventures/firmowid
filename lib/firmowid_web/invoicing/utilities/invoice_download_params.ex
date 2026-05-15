defmodule FirmowidWeb.Invoicing.Utilities.InvoiceDownloadParams do
  @moduledoc """
  Shared codecs for invoice PDF and monthly batch-download query params.
  """

  alias FirmowidWeb.Infrastructure.Utilities.PolishValues

  @include_internal_note_key "dolacz_komentarz_wewnetrzny"

  @batch_defaults %{
    include_digital: true,
    include_ksef: false,
    include_photos: false,
    include_sales: true,
    include_internal_note: true
  }

  @type batch_options :: %{
          required(:include_digital) => boolean(),
          required(:include_ksef) => boolean(),
          required(:include_photos) => boolean(),
          required(:include_sales) => boolean(),
          required(:include_internal_note) => boolean()
        }

  @doc """
  Parses monthly batch-download filters from request params.
  """
  @spec parse_batch_options(map()) :: batch_options()
  def parse_batch_options(params) when is_map(params) do
    %{
      include_digital: parse_boolean(params, "dolacz_cyfrowe", @batch_defaults.include_digital),
      include_ksef: parse_boolean(params, "dolacz_ksef", @batch_defaults.include_ksef),
      include_photos: parse_boolean(params, "dolacz_zdjecia", @batch_defaults.include_photos),
      include_sales: parse_boolean(params, "dolacz_sprzedazowe", @batch_defaults.include_sales),
      include_internal_note: parse_boolean(params, @include_internal_note_key, @batch_defaults.include_internal_note)
    }
  end

  @doc """
  Encodes the monthly batch-download query string.
  """
  @spec encode_month_download_query(Date.t(), map()) :: String.t()
  def encode_month_download_query(%Date{} = month, options) when is_map(options) do
    normalized_options = Map.merge(@batch_defaults, Map.take(options, Map.keys(@batch_defaults)))

    URI.encode_query(
      miesiac: Date.to_iso8601(month),
      dolacz_cyfrowe: PolishValues.encode_boolean(normalized_options.include_digital),
      dolacz_ksef: PolishValues.encode_boolean(normalized_options.include_ksef),
      dolacz_zdjecia: PolishValues.encode_boolean(normalized_options.include_photos),
      dolacz_sprzedazowe: PolishValues.encode_boolean(normalized_options.include_sales),
      dolacz_komentarz_wewnetrzny: PolishValues.encode_boolean(normalized_options.include_internal_note)
    )
  end

  @doc """
  Parses the internal-note flag from PDF download params.
  """
  @spec parse_include_internal_note(map()) :: boolean()
  def parse_include_internal_note(params) when is_map(params) do
    parse_boolean(params, @include_internal_note_key, true)
  end

  @doc """
  Encodes the internal-note PDF query string using Polish keys and values.
  """
  @spec encode_pdf_query(boolean()) :: String.t()
  def encode_pdf_query(include_internal_note) when is_boolean(include_internal_note) do
    URI.encode_query(dolacz_komentarz_wewnetrzny: PolishValues.encode_boolean(include_internal_note))
  end

  defp parse_boolean(params, key, default) do
    params
    |> Map.get(key, PolishValues.encode_boolean(default))
    |> PolishValues.parse_boolean()
    |> case do
      nil -> default
      parsed -> parsed
    end
  end
end
