defmodule FirmowidWeb.Infrastructure.Components.BlobProcessingToasts do
  @moduledoc """
  Shared LiveToast helpers for blob AI/processing failures.
  """

  use FirmowidWeb, :html

  import FirmowidWeb.DesignSystem.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Ash.Blobs.Blob
  alias FirmowidWeb.Invoicing.Utilities.Navigation

  @doc """
  Shows an error toast for a failed blob processing result.
  """
  @spec show_failure_toast(Blob.t()) :: any()
  def show_failure_toast(%Blob{original_filename: filename, processing_metadata: metadata}) do
    case processing_failure_reason(metadata) do
      :duplicate_ksef_invoice ->
        LiveToast.send_toast(
          :info,
          processing_failure_message(metadata, filename),
          title: "Duplikat faktury",
          action: fn assigns ->
            assigns = assign(assigns, :cost_invoice_id, duplicate_cost_invoice_id(metadata))

            ~H"""
            <.link
              kind="unstyled"
              class="text-bold text-sm underline"
              navigate={Navigation.cost_invoice_show_path(@cost_invoice_id)}
            >
              Wyświetl <.icon name="hero-arrow-right-solid" class="size-3" />
            </.link>
            """
          end
        )

      :invalid_document ->
        LiveToast.send_toast(
          :error,
          processing_failure_message(metadata, filename),
          title: "Nieprawidłowy dokument"
        )

      :missing_salary_metadata ->
        LiveToast.send_toast(
          :error,
          processing_failure_message(metadata, filename),
          title: "Brak danych wynagrodzenia"
        )

      _ ->
        LiveToast.send_toast(
          :error,
          processing_failure_message(metadata, filename),
          title: "Nie udało się wgrać pliku"
        )
    end
  end

  @doc """
  Shows a success toast for a successfully processed blob.
  """
  @spec show_success_toast(Blob.t(), atom() | nil) :: any()
  def show_success_toast(blob, type \\ nil)

  def show_success_toast(%Blob{}, :employment_contract) do
    LiveToast.send_toast(:success, "Umowa została pomyślnie dodana.")
  end

  def show_success_toast(%Blob{}, _) do
    LiveToast.send_toast(:success, "Plik został pomyślnie przesłany.")
  end

  defp processing_failure_reason(%{"error_code" => "invalid_document"}), do: :invalid_document
  defp processing_failure_reason(%{error_code: "invalid_document"}), do: :invalid_document
  defp processing_failure_reason(%{"error" => ":invalid_document"}), do: :invalid_document
  defp processing_failure_reason(%{error: ":invalid_document"}), do: :invalid_document

  defp processing_failure_reason(%{"error_code" => "duplicate_ksef_invoice"}), do: :duplicate_ksef_invoice

  defp processing_failure_reason(%{error_code: "duplicate_ksef_invoice"}), do: :duplicate_ksef_invoice

  defp processing_failure_reason(%{"error_code" => "missing_salary_metadata"}), do: :missing_salary_metadata

  defp processing_failure_reason(%{error_code: "missing_salary_metadata"}), do: :missing_salary_metadata

  defp processing_failure_reason(%{"error" => ":missing_salary_metadata"}), do: :missing_salary_metadata

  defp processing_failure_reason(%{error: ":missing_salary_metadata"}), do: :missing_salary_metadata

  defp processing_failure_reason(_), do: :processing_failed

  defp duplicate_cost_invoice_id(%{"cost_invoice_id" => id}), do: id
  defp duplicate_cost_invoice_id(%{cost_invoice_id: id}), do: id

  defp processing_failure_message(%{"error_message" => message}, _filename) when is_binary(message), do: message

  defp processing_failure_message(%{error_message: message}, _filename) when is_binary(message), do: message

  defp processing_failure_message(_metadata, filename), do: filename
end
