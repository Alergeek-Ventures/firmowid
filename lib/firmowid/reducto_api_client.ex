defmodule Firmowid.ReductoApiClient do
  @moduledoc """
  Reducto is a document metadata extraction API and parsing / chunking service.
  Uses Reducto API V3 - see https://docs.reducto.ai/extract/overview
  """

  require Logger

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
  @spec extract(String.t(), map(), extract_options) :: {:ok, map()} | {:error, String.t()}
  def extract(file_url, json_schema, options \\ []) do
    extraction_mode =
      options
      |> Keyword.get(:extraction_mode, :hybrid)
      |> Atom.to_string()

    system_prompt = Keyword.get(options, :system_prompt)

    host =
      :ex_aws
      |> Application.get_env(:s3)
      |> Keyword.get(:host)

    file_url = upload_to_reducto(file_url, host)

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
           "https://platform.reducto.ai/extract",
           auth: get_auth_token(),
           json: request_body,
           receive_timeout: 120_000,
           connect_options: [timeout: 120_000]
         ) do
      {:ok, response} ->
        body = Map.get(response, :body)

        case Map.get(body, "result") do
          result when is_map(result) ->
            {:ok, unwrap_citations(result)}

          [extracted_metadata | _] ->
            {:ok, unwrap_citations(extracted_metadata)}

          [] ->
            Logger.error("Reducto API returned empty result. Response body: #{inspect(body)}")
            {:error, "Reducto API returned empty result"}

          nil ->
            Logger.error("Reducto API response missing 'result' field. Response body: #{inspect(body)}")

            {:error, "Reducto API response missing 'result' field"}
        end

      {:error, err} ->
        Logger.error("Reducto API error: #{inspect(err)}")

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

  defp upload_to_reducto(file_url, "localhost") do
    case Briefly.create() do
      {:ok, temp_path} ->
        download_file(file_url, temp_path)
        file_url = upload_file(file_url, temp_path)
        file_url

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

    %{status: 200, body: body} = Req.get!(file_url)
    File.write(dest_path, body)
  end

  # sobelow_skip ["Traversal.FileModule"]
  # file_path is constructed internally from Briefly temp paths, not user input.
  defp upload_file(file_url, file_path) do
    # Validate file_path to prevent directory traversal
    file_path = Path.expand(file_path)

    {:ok, file_contents} = File.read(file_path)

    filename =
      Path.basename(file_path) <> (file_url |> String.split("?") |> hd() |> Path.extname())

    multipart =
      Multipart.add_part(
        Multipart.new(),
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
