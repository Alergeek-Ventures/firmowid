defmodule FirmowidWeb.CostInvoicesApiController do
  use FirmowidWeb, :controller

  alias Firmowid.CostInvoices

  action_fallback FirmowidWeb.FallbackController

  def create(conn, %{"blob" => blob_params}) do
    with {:ok, blob} <-
           CostInvoices.upload_cost_invoice(
             blob_params.path,
             blob_params.content_type,
             blob_params.filename
           ) do
      conn
      |> json(%{
        message: "Cost invoice uploaded successfully",
        blob_id: blob.id
      })
    else
      {:error, {:blob_already_exists, _checksum}} ->
        conn
        |> put_status(:conflict)
        |> put_view(FirmowidWeb.ErrorJSON)
        |> render(:error, error: "Cost invoice already exists")

      {:error, :unsupported_content_type} ->
        conn
        |> put_status(:unprocessable_entity)
        |> put_view(FirmowidWeb.ErrorJSON)
        |> render(:error, error: "Unsupported content type")

      {:error, _} ->
        conn
        |> put_status(:unprocessable_entity)
        |> put_view(FirmowidWeb.ErrorJSON)
        |> render(:error, error: "Invalid blob")
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> put_view(FirmowidWeb.ErrorJSON)
    |> render(:error, error: "Missing blob parameter")
  end
end
