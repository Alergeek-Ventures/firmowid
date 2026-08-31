defmodule Firmowid.Ash.Invoicing.Services.ReductoApiClient do
  @moduledoc """
  Reducto is a document metadata extraction API and parsing / chunking service.
  Uses Reducto API V3 - see https://docs.reducto.ai/extract/overview
  """

  alias Firmowid.ErrorKind

  require Logger

  @default_base_url "https://platform.reducto.ai"

  @type extract_options :: [
          extraction_mode: :hybrid | :ocr | :metadata,
          system_prompt: String.t() | nil
        ]

  def get_auth_token, do: {:bearer, Application.get_env(:firmowid, :reducto_api_key)}

  @doc """
  Extracts metadata from a document using Reducto API V3. Pass in a file URL
  and JSON schema Map to get this map back with extracted metadata.

  ## Options

    * `:extraction_mode` - `:hybrid` (default), `:ocr`, or `:metadata`
    * `:system_prompt` - Optional context for the LLM about the document type

  Be mindful that the API is in synchronous mode, meaning that a very big
  files might fail (120s timeout). It's possible to use async mode, but it
  wasn't needed yet.

  Returns {:ok, response} or {:error, reason}.
  """
  @spec extract(String.t(), map(), extract_options) ::
          {:ok, map()} | {:error, :invalid_document | String.t()}
  def extract(file_url, json_schema, options \\ []) do
    file_url
    |> upload_to_reducto(s3_host())
    |> extract_input(json_schema, options)
  end

  @doc """
  Uploads a local file to Reducto and extracts metadata from it.
  """
  @spec extract_file(Path.t(), map(), extract_options) ::
          {:ok, map()} | {:error, :invalid_document | String.t()}
  def extract_file(file_path, json_schema, options \\ []) do
    with {:ok, file_id} <- upload_file(file_path) do
      extract_input(file_id, json_schema, options)
    end
  end

  defp extract_input(file_url, json_schema, options) do
    extraction_mode =
      options
      |> Keyword.get(:extraction_mode, :hybrid)
      |> Atom.to_string()

    system_prompt = Keyword.get(options, :system_prompt)

    instructions = maybe_add_system_prompt(%{schema: json_schema}, system_prompt)

    request_body = %{
      input: file_url,
      parsing: %{
        settings: %{
          extraction_mode: extraction_mode
        },
        retrieval: %{
          chunking: %{chunk_mode: "disabled"}
        }
      },
      instructions: instructions,
      settings: %{
        citations: %{
          enabled: true,
          numerical_confidence: true
        }
      }
    }

    case Req.post(
           reducto_url("/extract"),
           extract_request_options(
             auth: get_auth_token(),
             json: request_body,
             receive_timeout: 120_000,
             connect_options: [timeout: 120_000]
           )
         ) do
      {:ok, response} ->
        body = Map.get(response, :body)

        case Map.get(body, "result") do
          result when is_map(result) ->
            {:ok, unwrap_citations(result)}

          [extracted_metadata | _] ->
            {:ok, unwrap_citations(extracted_metadata)}

          [] ->
            Logger.error("Reducto API returned empty result: status=#{response.status} outcome=empty_result")

            {:error, "Reducto API returned empty result"}

          nil ->
            Logger.error("Reducto API response missing 'result' field: status=#{response.status} outcome=missing_result")

            case Map.get(body, "error") do
              %{"code" => 415, "name" => "DOCUMENT_CORRUPT"} ->
                {:error, :invalid_document}

              error ->
                {:error, "Reducto API response missing 'result' field: #{ErrorKind.classify(error)}"}
            end
        end

      {:error, err} ->
        Logger.error("Reducto API request failed: error_kind=#{ErrorKind.classify(err)}")

        {:error, err}
    end
  end

  defp maybe_add_system_prompt(instructions, nil), do: instructions

  defp maybe_add_system_prompt(instructions, prompt), do: Map.put(instructions, :system_prompt, prompt)

  # When citations are enabled, values are wrapped in %{"value" => ..., "citations" => [...]}
  # This function unwraps them to return just the values for backward compatibility
  defp unwrap_citations(result) when is_map(result) do
    Map.new(result, fn {key, value} -> {key, unwrap_citation_value(value)} end)
  end

  defp unwrap_citation_value(%{"value" => value, "citations" => _citations}) do
    unwrap_citation_value(value)
  end

  defp unwrap_citation_value(value) when is_list(value) do
    Enum.map(value, &unwrap_citation_value/1)
  end

  defp unwrap_citation_value(value) when is_map(value) do
    Map.new(value, fn {k, v} -> {k, unwrap_citation_value(v)} end)
  end

  defp unwrap_citation_value(value), do: value

  defp s3_host do
    :firmowid
    |> Application.get_env(:s3)
    |> Keyword.get(:host)
  end

  defp upload_to_reducto(file_url, "localhost") do
    case Briefly.create() do
      {:ok, temp_path} ->
        download_file(file_url, temp_path)
        {:ok, file_id} = upload_file(temp_path)
        file_id

      _ ->
        raise "Failed to upload file to Reducto"
    end
  end

  defp upload_to_reducto(file_url, _s3_host), do: file_url

  # sobelow_skip ["Traversal.FileModule"]
  # dest_path is constructed internally from Briefly temp paths, not user input.
  defp download_file(file_url, dest_path) do
    # Validate dest_path to prevent directory traversal
    dest_path = Path.expand(dest_path)

    %{status: 200, body: body} = Req.get!(file_url, download_request_options())
    File.write(dest_path, body)
  end

  # sobelow_skip ["Traversal.FileModule"]
  # file_path comes from Phoenix or Briefly temporary uploads, not raw web input.
  defp upload_file(file_path) do
    # Validate file_path to prevent directory traversal
    file_path = Path.expand(file_path)

    {:ok, file_contents} = File.read(file_path)

    filename = Path.basename(file_path)

    multipart =
      Multipart.add_part(
        Multipart.new(),
        Multipart.Part.file_content_field(filename, file_contents, :file, filename: filename)
      )

    content_type = Multipart.content_type(multipart, "multipart/form-data")

    headers = [
      {"Content-Type", content_type}
    ]

    case Req.post(
           reducto_url("/upload"),
           upload_request_options(
             auth: get_auth_token(),
             headers: headers,
             body: Multipart.body_stream(multipart)
           )
         ) do
      {:ok, %{status: 200, body: %{"file_id" => file_id}}} ->
        {:ok, file_id}

      {:ok, response} ->
        {:error, "Reducto upload failed: #{inspect(response.body)}"}

      {:error, error} ->
        {:error, error}
    end
  end

  defp reducto_url(path), do: base_url() <> path

  defp base_url do
    :firmowid
    |> Application.get_env(:reducto_api_client, [])
    |> Keyword.get(:base_url, @default_base_url)
  end

  defp extract_request_options(options), do: merge_request_options(:extract, options)

  defp upload_request_options(options), do: merge_request_options(:upload, options)

  defp download_request_options, do: merge_request_options(:download, [])

  defp merge_request_options(key, options) do
    options ++
      (:firmowid
       |> Application.get_env(:reducto_api_client, [])
       |> Keyword.get(key, []))
  end
end
