defmodule Firmowid.ReductoApiClient do
  @moduledoc """
  Reducto is a document metadata extraction API and parsing / chunking service
  (for RAG, unused at the moment).
  """

  @type extract_options :: [extraction_mode: :hybrid | :ocr | :metadata]

  def get_auth_token, do: {:bearer, Application.get_env(:firmowid, :reducto_api_key)}

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

    host =
      Application.get_env(:ex_aws, :s3)
      |> Keyword.get(:host)

    file_url =
      upload_to_reducto(file_url, host)

    with {:ok, response} <-
           Req.post(
             "https://platform.reducto.ai/extract",
             auth: get_auth_token(),
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

  defp upload_to_reducto(file_url, "localhost") do
    with {:ok, temp_path} <- Briefly.create(),
         _ <- download_file(file_url, temp_path),
         file_url <- upload_file(file_url, temp_path) do
      file_url
    else
      _ ->
        raise "Failed to upload file to Reducto"
    end
  end

  defp upload_to_reducto(file_url, _s3_host), do: file_url

  defp download_file(file_url, dest_path) do
    %{status: 200, body: body} = Req.get!(file_url)
    File.write(dest_path, body)
  end

  defp upload_file(file_url, file_path) do
    {:ok, file_contents} = File.read(file_path)

    filename = Path.basename(file_path) <> Path.extname(file_url |> String.split("?") |> hd())

    multipart =
      Multipart.new()
      |> Multipart.add_part(
        Multipart.Part.file_content_field(filename, file_contents, :file, filename: filename)
      )

    content_type = Multipart.content_type(multipart, "multipart/form-data")

    headers = [
      {"Content-Type", content_type}
    ]

    %{status: 200, body: %{"file_id" => file_url}} =
      Req.post!(
        "https://platform.reducto.ai/upload",
        auth: get_auth_token(),
        headers: headers,
        body: Multipart.body_stream(multipart)
      )

    file_url
  end
end
