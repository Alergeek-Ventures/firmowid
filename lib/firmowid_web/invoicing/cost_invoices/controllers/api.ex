defmodule FirmowidWeb.Invoicing.CostInvoices.Controllers.Api do
  @moduledoc false
  use FirmowidWeb, :controller

  alias Firmowid.CostInvoices
  alias FirmowidWeb.Infrastructure.Components.ErrorJson

  action_fallback FirmowidWeb.Infrastructure.Controllers.Fallback

  def create(conn, %{"blob" => blob_params}) do
    with :ok <- Bodyguard.permit(CostInvoices, :upload, conn.assigns.current_user),
         {:ok, blob} <-
           CostInvoices.upload_cost_invoice(
             blob_params.path,
             blob_params.content_type,
             blob_params.filename
           ) do
      json(conn, %{message: "Cost invoice uploaded successfully", blob_id: blob.id})
    else
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

      {:error, :unauthorized} ->
        {:error, :unauthorized}

      {:error, _} ->
        conn
        |> put_status(:unprocessable_entity)
        |> put_view(ErrorJson)
        |> render(:error, error: "Invalid blob")
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> put_view(ErrorJson)
    |> render(:error, error: "Missing blob parameter")
  end
end
