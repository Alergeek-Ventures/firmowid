defmodule Firmowid.ReductoApiClient do
  @moduledoc """
  Reducto is a document metadata extraction API and parsing / chunking service
  (for RAG, unused at the moment).
  """

  @type extract_options :: [extraction_mode: :hybrid | :ocr | :metadata]

  @doc """
  Extracts metadata from a document using Reducto API. Pass in a file URL
  and JSON schema Map to get this map back with extracted metadata.

  Be mindful that the API is in synchronous mode, meaning that a very big
  files might fail (120s timeout). It's possible to use async mode, but it
  wasn't needed yet.

  Returns {:ok, response} or {:error, reason}.
  """
  @spec extract(String.t(), map(), extract_options) :: {:ok, map()} | {:error, String.t()}
  def extract(file_url, json_schema, options \\ []) do
    extraction_mode =
      Keyword.get(options, :extraction_mode, :hybrid)
      |> Atom.to_string()

    with {:ok, response} <-
           Req.post(
             "https://v1.api.reducto.ai/extract",
             auth:
               {:bearer,
                "f6db515168d1b7c99dcecfd0517062dcbfd083a6ba1e42d0e3bcc623d832288087949aa99728f0d65ff5da7044e9fecc"},
             json: %{
               document_url: file_url,
               options: %{
                 extraction_mode: extraction_mode,
                 disable_chunking: true
               },
               async: %{
                 enabled: false
               },
               schema: json_schema
             },
             receive_timeout: 120_000,
             connect_options: [timeout: 120_000]
           ) do
      # Body is a list of dictionaries.
      # If disable_chunking is True (default), then it will be a list of length one.
      extracted_metadata = response |> Map.get(:body) |> Map.get("result") |> hd()

      {:ok, extracted_metadata}
    else
      {:error, err} ->
        Sentry.capture_exception(err)

        {:error, err}
    end
  end
end
