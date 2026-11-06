defmodule Firmowid.Delegations.CommandUpload do
  @moduledoc "Prepares order PDFs locally, keeping the stored file within 8 MB without changing page content."

  @max_file_size 8_000_000
  @max_input_size 32_000_000

  @doc "Maximum temporary input size for local, lossless PDF compression."
  @spec max_input_size() :: pos_integer()
  def max_input_size, do: @max_input_size

  @doc "Keeps small PDFs byte-for-byte; reduces larger unsigned PDFs without resampling images."
  @spec prepare(String.t()) ::
          {:ok, String.t()} | {:error, :too_large | :signed | :cannot_compress}
  # sobelow_skip ["Traversal.FileModule"]
  # path is allocated by Phoenix uploads or Briefly, not supplied as a web parameter.
  def prepare(path) do
    case File.stat!(path).size do
      size when size <= @max_file_size -> {:ok, path}
      size when size > @max_input_size -> {:error, :too_large}
      _size -> compress(path)
    end
  end

  defp compress(path) do
    with :ok <- safe_to_rewrite(path) do
      {:ok, output_path} = Briefly.create(extname: ".pdf")

      case System.cmd(
             "qpdf",
             [
               "--object-streams=generate",
               "--compress-streams=y",
               "--recompress-flate",
               "--compression-level=9",
               path,
               output_path
             ],
             stderr_to_stdout: true
           ) do
        {_output, 0} -> check_compressed_size(output_path)
        {_output, _status} -> discard_compressed_file(output_path)
      end
    end
  end

  defp safe_to_rewrite(path) do
    with {output, 0} <-
           System.cmd("qpdf", ["--json", "--json-key=qpdf", "--json-key=encrypt", path], stderr_to_stdout: true),
         {:ok, document} <- Jason.decode(output) do
      cond do
        signature?(document) -> {:error, :signed}
        document["encrypt"]["encrypted"] -> {:error, :cannot_compress}
        true -> :ok
      end
    else
      _error -> {:error, :cannot_compress}
    end
  end

  # Inspect parsed objects, including compressed object streams and escaped PDF names.
  # Even an empty signature field is kept intact rather than risking a signed document.
  defp signature?(value) when is_map(value) do
    Map.has_key?(value, "/ByteRange") or value["/Type"] == "/Sig" or
      value["/FT"] == "/Sig" or Enum.any?(Map.values(value), &signature?/1)
  end

  defp signature?(value) when is_list(value), do: Enum.any?(value, &signature?/1)
  defp signature?(_value), do: false

  # sobelow_skip ["Traversal.FileModule"]
  # path is the output file allocated by Briefly above, never a user-supplied path.
  defp check_compressed_size(path) do
    if File.stat!(path).size <= @max_file_size,
      do: {:ok, path},
      else: discard_compressed_file(path)
  end

  # sobelow_skip ["Traversal.FileModule"]
  # This is only called with the output allocated by Briefly, not the original upload.
  defp discard_compressed_file(path) do
    File.rm!(path)
    {:error, :cannot_compress}
  end
end
