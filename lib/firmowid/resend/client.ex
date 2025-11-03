defmodule Firmowid.Resend.Client do
  @moduledoc """
  Resend API client for inbound email operations.

  Uses the official Resend Elixir library's lower-level client abstraction
  to access inbound email endpoints not yet exposed in higher-level APIs.
  """

  @doc """
  Retrieves an email's content by email_id.
  Returns `{:ok, %{html: ..., text: ...}}` or `{:error, term}`.
  """
  def get_email(email_id) do
    client = resend_client()

    case Resend.Client.get(client, :raw, "/emails/receiving/#{email_id}") do
      {:ok, body} ->
        {:ok, %{html: Map.get(body, "html"), text: Map.get(body, "text")}}

      {:error, _reason} = error ->
        error
    end
  end

  @doc """
  Lists attachments for an email by email_id.
  Returns `{:ok, [%{filename: ..., content_type: ..., download_url: ...}]}` or `{:error, term}`.
  """
  def list_attachments(email_id) do
    client = resend_client()

    case Resend.Client.get(client, :raw, "/emails/receiving/#{email_id}/attachments") do
      # Handle paginated response format
      {:ok, %{"data" => attachments_list}} when is_list(attachments_list) ->
        attachments =
          Enum.map(attachments_list, fn attachment ->
            %{
              id: Map.get(attachment, "id"),
              filename: Map.get(attachment, "filename"),
              content_type: Map.get(attachment, "content_type"),
              download_url: Map.get(attachment, "download_url"),
              size: Map.get(attachment, "size")
            }
          end)

        {:ok, attachments}

      {:error, _reason} = error ->
        error
    end
  end

  @doc """
  Downloads an attachment from a presigned URL.
  Returns `{:ok, binary}` or `{:error, term}`.
  """
  def download_attachment(url) do
    case Req.get(url) do
      {:ok, %Req.Response{status: 200, body: body}} when is_binary(body) ->
        {:ok, body}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp resend_client do
    api_key = Application.fetch_env!(:firmowid, :resend_api_key)
    Resend.client(api_key: api_key)
  end
end
