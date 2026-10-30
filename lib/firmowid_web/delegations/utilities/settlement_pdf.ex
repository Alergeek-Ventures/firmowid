defmodule FirmowidWeb.Delegations.Utilities.SettlementPdf do
  @moduledoc "Loads and renders the canonical two-page delegation settlement PDF."

  alias Firmowid.Delegations
  alias Firmowid.Payroll
  alias FirmowidWeb.Delegations.Utilities.SettlementDocument
  alias FirmowidWeb.Infrastructure.Utilities.PdfHelpers

  @readable_statuses [:awaiting_signature, :submitted, :complete]

  @doc "Loads all data used by both the settlement preview and generated PDF."
  @spec load(String.t(), map()) :: {:ok, SettlementDocument.t()} | {:error, term()}
  def load(reference, scope) do
    with {:ok, %{} = delegation} <-
           Delegations.get_delegation_by_reference(reference,
             scope: scope,
             not_found_error?: false,
             load: [
               member: :user,
               organization: [avatar_blob: [:url]],
               expenses: [:blob, :statement_blob, :related_blobs]
             ]
           ),
         true <- delegation.status in @readable_statuses,
         {:ok, employment_contract} <-
           Payroll.load_current_contract(delegation.member_id, scope: scope) do
      logo_data_uri =
        delegation.organization.avatar_blob
        |> then(&if(&1, do: &1.url))
        |> PdfHelpers.url_to_data_uri()

      {:ok,
       in_polish(fn ->
         SettlementDocument.build(delegation, employment_contract, logo_data_uri)
       end)}
    else
      {:ok, nil} -> {:error, :not_found}
      false -> {:error, :not_found}
      error -> error
    end
  end

  @doc "Generates a binary PDF for a canonical settlement document model."
  @spec generate(SettlementDocument.t()) :: {:ok, binary()} | {:error, term()}
  def generate(document) do
    html =
      in_polish(fn ->
        PdfHelpers.render_pdf_html(
          FirmowidWeb.Delegations.Components.SettlementPdf,
          :document,
          document: document,
          footer_logo_data_uri:
            PdfHelpers.file_to_data_uri(Path.join(:code.priv_dir(:firmowid), "static/images/figurine.png"))
        )
      end)

    renderer().render(html)
  end

  # The settlement is a Polish document, whatever language the employee uses the app in.
  defp in_polish(fun), do: Gettext.with_locale(Firmowid.Gettext, "pl", fun)

  defp renderer do
    Application.get_env(
      :firmowid,
      :settlement_pdf_renderer,
      FirmowidWeb.Delegations.Utilities.SettlementPdf.ChromicRenderer
    )
  end
end

defmodule FirmowidWeb.Delegations.Utilities.SettlementPdf.ChromicRenderer do
  @moduledoc "ChromicPDF renderer for delegation settlements."

  alias Firmowid.Invoicing.Services.PdfUtils

  @doc "Renders already composed settlement HTML into an A4 PDF binary."
  @spec render(binary()) :: {:ok, binary()} | {:error, term()}
  def render(html) do
    PdfUtils.render_html_to_pdf(html,
      page_size: "A4",
      scale: 1.0,
      evaluate: %{
        expression: "document.body.style.margin = '0'; document.body.style.padding = '0';"
      }
    )
  end
end
