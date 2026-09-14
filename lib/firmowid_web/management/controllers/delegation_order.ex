defmodule FirmowidWeb.Management.Controllers.DelegationOrder do
  @moduledoc "Controller for downloading business trip order PDFs."

  use FirmowidWeb, :controller

  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Delegations
  alias FirmowidWeb.Infrastructure.Utilities.PdfHelpers

  @dialyzer {:no_return, pdf: 2}

  # sobelow_skip ["Traversal.SendFile"]
  # The PDF path is allocated by ChromicPDF, never supplied by a request parameter.
  def pdf(conn, %{"employee_id" => employee_id, "reference" => reference}) do
    scope = conn.assigns.ash_scope

    with true <- conn.assigns.current_user.role == :admin,
         {:ok, employee} <- Core.get_org_user(%{id: employee_id}, scope: scope),
         {:ok, delegation} <- Delegations.get_delegation_by_reference(reference, scope: scope),
         true <- delegation.user_id == employee.id do
      html =
        PdfHelpers.render_pdf_html(
          FirmowidWeb.Management.Components.DelegationOrderPdf,
          :order,
          employee: employee,
          delegation: delegation,
          footer_logo_data_uri:
            PdfHelpers.file_to_data_uri(Path.join(:code.priv_dir(:firmowid), "static/images/figurine.png"))
        )

      {:ok, result} =
        ChromicPDF.print_to_pdf({:html, html},
          output: fn path ->
            conn
            |> put_resp_header(
              "content-disposition",
              "attachment; filename=\"#{filename(employee)}\""
            )
            |> send_file(200, path)
          end,
          page_size: "A4",
          evaluate: %{
            expression: "document.body.style.margin = '0'; document.body.style.padding = '0';"
          },
          print_to_pdf: %{
            marginTop: 0,
            marginLeft: 0,
            marginRight: 0,
            marginBottom: 0,
            printBackground: true
          }
        )

      result
    else
      _ ->
        conn
        |> LiveToast.put_toast(:error, "Nie masz dostępu do tej delegacji.")
        |> redirect(to: ~p"/zarzadzanie/pracownicy")
    end
  end

  defp filename(employee) do
    initials =
      (employee.name || employee.email)
      |> String.split()
      |> Enum.map_join(&String.first/1)
      |> String.upcase()

    "Polecenie_wyjazdu_#{initials}.pdf"
  end
end
