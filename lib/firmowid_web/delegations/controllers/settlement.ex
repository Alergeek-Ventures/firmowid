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
        conn |> put_status(:not_found) |> text(gettext("Settlement not found."))

      {:error, %Ash.Error.Forbidden{}} ->
        conn |> put_status(:not_found) |> text(gettext("Settlement not found."))
    end
  end
end
