defmodule FirmowidUI.Components.UploadErrors do
  @moduledoc """
  Messages for files that `allow_upload/3` refused, so a rejected file does not fail silently.
  """

  use FirmowidUI, :html

  alias Phoenix.LiveView.Rendered

  @doc """
  Renders each reason the upload refused the chosen files, once.
  """
  @spec upload_error_messages(map()) :: Rendered.t()
  attr :upload, Phoenix.LiveView.UploadConfig, required: true
  attr :not_accepted, :string, required: true, doc: "Names the file types the upload accepts."
  attr :class, :any, default: nil

  def upload_error_messages(assigns) do
    ~H"""
    <p :for={error <- refusals(@upload)} class={["text-sm text-brick-600", @class]}>
      {message(error, @not_accepted)}
    </p>
    """
  end

  defp refusals(upload) do
    Enum.uniq(upload_errors(upload) ++ Enum.flat_map(upload.entries, &upload_errors(upload, &1)))
  end

  defp message(:too_large, _not_accepted), do: gettext("The file is too large.")
  defp message(:too_many_files, _not_accepted), do: gettext("You can upload only one file.")
  defp message(:not_accepted, not_accepted), do: not_accepted
end
