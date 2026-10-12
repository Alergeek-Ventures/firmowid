defmodule FirmowidWeb.Delegations.Controllers.Settlement do
  @moduledoc "Authenticated download endpoint for delegation settlement PDFs."

  use FirmowidWeb, :controller

  alias FirmowidWeb.Delegations.Utilities.SettlementDocument
  alias FirmowidWeb.Delegations.Utilities.SettlementPdf

  def download(conn, %{"reference" => reference}) do
    with {:ok, document} <- SettlementPdf.load(reference, conn.assigns.ash_scope),
         {:ok, pdf} <- SettlementPdf.generate(document) do
      send_download(conn, {:binary, pdf},
        filename: SettlementDocument.filename(document),
        content_type: "application/pdf"
      )
    else
      {:error, :not_found} ->
        send_resp(conn, :not_found, "Nie znaleziono rozliczenia.")

      {:error, %Ash.Error.Forbidden{}} ->
        send_resp(conn, :not_found, "Nie znaleziono rozliczenia.")
    end
  end
end
