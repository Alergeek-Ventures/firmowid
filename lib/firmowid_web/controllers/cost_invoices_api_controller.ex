defmodule FirmowidWeb.CostInvoicesApiController do
  use FirmowidWeb, :controller

  alias Firmowid.CostInvoices

  action_fallback FirmowidWeb.FallbackController

  def create(conn, %{"document" => document_params}) do
    with {:ok, blob} <-
           CostInvoices.upload_cost_invoice(
             document_params.path,
             document_params.content_type,
             document_params.filename
           ) do
      conn
      |> json(%{
        message: "Document uploaded successfully",
        blob_id: blob.id
      })
    else
      {:error, {:blob_already_exists, _checksum}} ->
        conn
        |> put_status(:conflict)
        |> put_view(FirmowidWeb.ErrorJSON)
        |> render(:error, error: "Document already exists")

      {:error, :unsupported_content_type} ->
        conn
        |> put_status(:unprocessable_entity)
        |> put_view(FirmowidWeb.ErrorJSON)
        |> render(:error, error: "Unsupported content type")

      {:error, _} ->
        conn
        |> put_status(:unprocessable_entity)
        |> put_view(FirmowidWeb.ErrorJSON)
        |> render(:error, error: "Invalid document")
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> put_view(FirmowidWeb.ErrorJSON)
    |> render(:error, error: "Missing document parameter")
  end
end
