defmodule FirmowidWeb.Invoicing.CostInvoices.Controllers.Api do
  @moduledoc false
  use FirmowidWeb, :controller

  alias Firmowid.Ash.Invoicing
  alias FirmowidWeb.Infrastructure.Components.ErrorJson

  action_fallback FirmowidWeb.Infrastructure.Controllers.Fallback

  def create(%{assigns: %{current_user: %{role: :admin}}} = conn, %{"blob" => blob_params}) do
    case Invoicing.upload_cost_invoice(
           blob_params.path,
           blob_params.content_type,
           blob_params.filename
         ) do
      {:ok, blob} ->
        json(conn, %{message: "Cost invoice uploaded successfully", blob_id: blob.id})

      {:error, {:blob_already_exists, _checksum}} ->
        conn
        |> put_status(:conflict)
        |> put_view(ErrorJson)
        |> render(:error, error: "Cost invoice already exists")

      {:error, :unsupported_content_type} ->
        conn
        |> put_status(:unprocessable_entity)
        |> put_view(ErrorJson)
        |> render(:error, error: "Unsupported content type")

      {:error, _} ->
        conn
        |> put_status(:unprocessable_entity)
        |> put_view(ErrorJson)
        |> render(:error, error: "Invalid blob")
    end
  end

  def create(%{assigns: %{current_user: %{role: :admin}}} = conn, _params) do
    conn
    |> put_status(:bad_request)
    |> put_view(ErrorJson)
    |> render(:error, error: "Missing blob parameter")
  end

  def create(_conn, _params) do
    {:error, :unauthorized}
  end
end
