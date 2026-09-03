defmodule Firmowid.Ash.Core.Services.GoogleAvatarImporter do
  @moduledoc """
  Imports a Google profile picture into the local avatar blob storage.

  The importer is best-effort: if the avatar cannot be fetched or persisted,
  the user can still authenticate successfully.
  """
  alias Firmowid.Ash.Blobs
  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Core.User
  alias Firmowid.Ash.Scope
  alias Firmowid.ErrorKind

  require Logger

  @default_content_type "image/jpeg"
  @default_filename "google-avatar.jpg"
  @request_opts [connect_options: [timeout: 3_000], receive_timeout: 5_000]

  @doc """
  Imports the Google avatar for a user who belongs to an organization and does
  not yet have a local avatar.

  Returns `{:ok, user}` in all non-fatal cases to avoid breaking login.
  """
  @spec maybe_import(User.t(), map()) :: {:ok, User.t()}
  def maybe_import(%User{} = user, user_info) when is_map(user_info) do
    cond do
      is_nil(user.organization_id) ->
        {:ok, user}

      not is_nil(user.avatar_blob_id) ->
        {:ok, user}

      not is_binary(picture_url(user_info)) ->
        {:ok, user}

      true ->
        import_avatar(user, picture_url(user_info))
    end
  end

  def maybe_import(%User{} = user, _user_info), do: {:ok, user}

  defp import_avatar(%User{} = user, picture_url) do
    scope = %Scope{actor: user, tenant: user.organization_id}

    with {:ok, response} <- fetch_avatar(picture_url),
         {:ok, content_type} <- image_content_type(response),
         {:ok, path} <- write_avatar_to_temp_file(response.body, content_type) do
      try do
        with {:ok, blob} <-
               Blobs.create_blob(path, content_type, original_filename(content_type), scope: scope),
             {:ok, updated_user} <-
               Core.update_user_avatar(user, %{avatar_blob_id: blob.id}, scope: scope) do
          {:ok, updated_user}
        else
          {:error, reason} ->
            Logger.warning("Skipping Google avatar import",
              user_id: user.id,
              error_kind: ErrorKind.classify(reason)
            )

            {:ok, user}
        end
      after
        cleanup_temp_file(path)
      end
    else
      {:error, reason} ->
        Logger.warning("Skipping Google avatar import",
          user_id: user.id,
          error_kind: ErrorKind.classify(reason)
        )

        {:ok, user}
    end
  end

  defp fetch_avatar(url) do
    case Req.get(url, @request_opts) do
      {:ok, %Req.Response{status: 200, body: body} = response} when is_binary(body) ->
        {:ok, response}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:unexpected_status, status}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  defp image_content_type(%Req.Response{} = response) do
    response
    |> Req.Response.get_header("content-type")
    |> List.first(@default_content_type)
    |> String.split(";", parts: 2)
    |> List.first()
    |> case do
      "image/" <> _ = content_type -> {:ok, content_type}
      other -> {:error, {:unsupported_content_type, other}}
    end
  end

  # sobelow_skip ["Traversal.FileModule"]
  # Path comes from Briefly.create/1 in the OS temp directory, not web input.
  defp write_avatar_to_temp_file(binary, content_type) do
    extension = List.first(MIME.extensions(content_type), "jpg")

    with {:ok, path} <- Briefly.create(extname: ".#{extension}"),
         :ok <- File.write(path, binary) do
      {:ok, path}
    else
      {:error, reason} -> {:error, {:file_write_failed, reason}}
    end
  end

  defp original_filename(content_type) do
    extension = List.first(MIME.extensions(content_type), "jpg")
    Path.rootname(@default_filename, ".jpg") <> ".#{extension}"
  end

  # sobelow_skip ["Traversal.FileModule"]
  # path comes from Briefly.create/1 in write_avatar_to_temp_file/2, not web input.
  defp cleanup_temp_file(path), do: File.rm(path)

  defp picture_url(user_info) do
    user_info["picture"] || user_info["avatar_url"] || user_info["image"]
  end
end
