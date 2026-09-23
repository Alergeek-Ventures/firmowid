defmodule FirmowidWeb.Management.Controllers.DelegationOrder do
  @moduledoc "Controller for downloading business trip order PDFs."

  use FirmowidWeb, :controller

  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Delegations
  alias Firmowid.Ash.Invoicing.Services.PdfUtils
  alias Firmowid.Ash.Payroll
  alias FirmowidWeb.Infrastructure.Utilities.PdfHelpers

  # PDF downloads are Gotenberg-rendered binaries, not user-controlled HTML.
  # sobelow_skip ["XSS.SendResp"]
  def pdf(conn, %{"employee_id" => employee_id, "reference" => reference}) do
    scope = conn.assigns.ash_scope

    with true <- conn.assigns.current_user.role == :admin,
         {:ok, employee} <- Core.get_org_user(%{id: employee_id}, scope: scope),
         {:ok, delegation} <- Delegations.get_delegation_by_reference(reference, scope: scope),
         {:ok, employment_contract} <- Payroll.load_current_contract(employee.id, scope: scope),
         true <- delegation.user_id == employee.id,
         {:ok, pdf} <- render_pdf(employee, employment_contract, delegation) do
      conn
      |> put_resp_header(
        "content-disposition",
        "attachment; filename=\"#{filename(employee)}\""
      )
      |> put_resp_content_type("application/pdf")
      |> send_resp(200, pdf)
    else
      _ ->
        conn
        |> LiveToast.put_toast(:error, "Nie masz dostępu do tej delegacji.")
        |> redirect(to: ~p"/zarzadzanie/pracownicy")
    end
  end

  defp render_pdf(employee, employment_contract, delegation) do
    html =
      PdfHelpers.render_pdf_html(
        FirmowidWeb.Management.Components.DelegationOrderPdf,
        :order,
        employee: employee,
        employment_contract: employment_contract,
        delegation: delegation,
        footer_logo_data_uri:
          PdfHelpers.file_to_data_uri(Path.join(:code.priv_dir(:firmowid), "static/images/figurine.png"))
      )

    PdfUtils.render_html_to_pdf(html, scale: 1)
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
