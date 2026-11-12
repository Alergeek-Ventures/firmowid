defmodule FirmowidWeb.Management.Controllers.DelegationOrder do
  @moduledoc "Controller for downloading business trip order PDFs."

  use FirmowidWeb, :controller

  alias Firmowid.Core
  alias Firmowid.Delegations
  alias Firmowid.Invoicing.Services.PdfUtils
  alias Firmowid.Payroll
  alias FirmowidWeb.Infrastructure.Utilities.PdfHelpers
  alias FirmowidWeb.Management.Components.DelegationOrderPdf

  # PDF downloads are Gotenberg-rendered binaries, not user-controlled HTML.
  # sobelow_skip ["XSS.SendResp"]
  def pdf(conn, %{"employee_id" => employee_id, "reference" => reference}) do
    scope = conn.assigns.ash_scope

    with true <- conn.assigns.current_user.member.role == :admin,
         {:ok, employee} <- Core.get_org_user(%{id: employee_id}, scope: scope, load: [:member]),
         {:ok, delegation} <- Delegations.get_delegation_by_reference(reference, scope: scope),
         true <- delegation.member_id == employee.member.id do
      {:ok, employment_contract} = Payroll.load_current_contract(employee.member.id, scope: scope)
      {:ok, pdf} = render_pdf(employee, employment_contract, delegation)

      send_download(conn, {:binary, pdf},
        filename: DelegationOrderPdf.filename(employee),
        content_type: "application/pdf"
      )
    else
      false -> deny(conn)
      # A record outside the actor's reach reads as not found.
      {:error, %Ash.Error.Invalid{}} -> deny(conn)
    end
  end

  defp deny(conn) do
    conn
    |> LiveToast.put_toast(:error, gettext("You do not have access to this business trip."))
    |> redirect(to: ~p"/zarzadzanie/pracownicy")
  end

  defp render_pdf(employee, employment_contract, delegation) do
    html =
      PdfHelpers.render_pdf_html(
        DelegationOrderPdf,
        :order,
        employee: employee,
        employment_contract: employment_contract,
        delegation: delegation,
        footer_logo_data_uri:
          PdfHelpers.file_to_data_uri(Path.join(:code.priv_dir(:firmowid), "static/images/figurine.png"))
      )

    PdfUtils.render_html_to_pdf(html, scale: 1)
  end
end
