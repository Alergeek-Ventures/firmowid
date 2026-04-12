defmodule Firmowid.S3Client do
  @moduledoc """
  Thin S3 client built on Req + ReqS3.

  Keeps S3 operations used by the app in one place:

    * upload file from local path
    * upload binary payload
    * delete object
    * generate presigned GET URL
  """

  @type object_key :: String.t()

  @doc """
  Uploads a file from local disk to configured S3 bucket.
  """
  @spec upload_file!(Path.t(), object_key(), keyword()) :: Req.Response.t()
  # sobelow_skip ["Traversal.FileModule"]
  # path comes from internal upload temp files (Briefly/Phoenix), not raw user-controlled file paths.
  def upload_file!(path, object_key, opts \\ []) do
    stat = File.stat!(path)
    content_type = Keyword.get(opts, :content_type)

    Req.put!(req(),
      url: s3_url(bucket(), object_key),
      headers: put_content_type([content_length: stat.size], content_type),
      body: File.stream!(path, 64 * 1024, [])
    )
  end

  @doc """
  Uploads a binary payload to configured S3 bucket.
  """
  @spec upload_binary!(binary(), object_key(), keyword()) :: Req.Response.t()
  def upload_binary!(payload, object_key, opts \\ []) when is_binary(payload) do
    content_type = Keyword.get(opts, :content_type)

    Req.put!(req(), url: s3_url(bucket(), object_key), headers: put_content_type([], content_type), body: payload)
  end

  @doc """
  Deletes an object from configured S3 bucket.
  """
  @spec delete_object(object_key()) :: {:ok, Req.Response.t()} | {:error, term()}
  def delete_object(object_key) do
    Req.delete(req(), url: s3_url(bucket(), object_key))
  end

  @doc """
  Generates a presigned GET URL for an object key.
  """
  @spec presigned_get_url(object_key(), keyword()) :: {:ok, String.t()} | {:error, Exception.t()}
  def presigned_get_url(object_key, opts \\ []) do
    expires = Keyword.get(opts, :expires_in, 86_400)

    {:ok,
     ReqS3.presign_url(
       bucket: bucket(),
       key: object_key,
       method: :get,
       expires: expires,
       endpoint_url: endpoint_url(),
       access_key_id: aws_access_key_id(),
       secret_access_key: aws_secret_access_key()
     )}
  rescue
    error in [ArgumentError] ->
      {:error, error}
  end

  defp req do
    ReqS3.attach(Req.new(), aws_sigv4: aws_sigv4(), aws_endpoint_url_s3: endpoint_url())
  end

  defp aws_sigv4 do
    [
      service: :s3,
      access_key_id: aws_access_key_id(),
      secret_access_key: aws_secret_access_key(),
      region: aws_region()
    ]
  end

  defp bucket do
    Application.fetch_env!(:firmowid, :uploads_bucket)
  end

  defp aws_region do
    Keyword.get(s3_config(), :region, "us-east-1")
  end

  defp aws_access_key_id do
    Keyword.get(s3_config(), :access_key_id)
  end

  defp aws_secret_access_key do
    Keyword.get(s3_config(), :secret_access_key)
  end

  defp endpoint_url do
    s3_config = s3_config()

    case Keyword.get(s3_config, :host) do
      nil ->
        nil

      host ->
        scheme = Keyword.get(s3_config, :scheme, "https://")
        port = Keyword.get(s3_config, :port)
        "#{scheme}#{host}" <> maybe_port(port)
    end
  end

  defp maybe_port(nil), do: ""
  defp maybe_port(port), do: ":#{port}"

  defp s3_url(bucket, object_key), do: "s3://#{bucket}/#{object_key}"

  defp s3_config do
    Application.get_env(:firmowid, :s3, [])
  end

  defp put_content_type(headers, nil), do: headers
  defp put_content_type(headers, content_type), do: [{"content-type", content_type} | headers]
end
