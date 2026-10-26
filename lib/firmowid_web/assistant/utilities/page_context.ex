defmodule FirmowidWeb.Assistant.Utilities.PageContext do
  @moduledoc "Resolves the current product page to an assistant subject using the application's routes."

  alias FirmowidWeb.Core.Endpoint
  alias FirmowidWeb.Core.Router

  @subject_types %{
    FirmowidWeb.Invoicing.CostInvoices.Views.Show => :cost_invoice,
    FirmowidWeb.Invoicing.SalesInvoices.Views.Show => :sales_invoice,
    FirmowidWeb.Invoicing.SalesInvoices.Views.Edit => :sales_invoice,
    FirmowidWeb.Invoicing.SalesInvoices.Views.Summary => :sales_invoice,
    FirmowidWeb.Invoicing.Transactions.Views.Show => :transaction,
    FirmowidWeb.Management.Views.Employee => :employee,
    FirmowidWeb.Management.Views.Project => :project,
    FirmowidWeb.Management.Views.ProjectForm => :project
  }

  @doc "Returns the record reference for a detail page, or nil for pages without a subject."
  @spec subject(String.t()) :: map() | nil
  def subject(path) do
    host = Endpoint.url() |> URI.parse() |> Map.fetch!(:host)

    case Phoenix.Router.route_info(Router, "GET", path, host) do
      %{path_params: %{"id" => id}, phoenix_live_view: {view, _action, _options, _session}} ->
        if type = Map.get(@subject_types, view), do: %{subject_type: type, subject_id: id}

      _route ->
        nil
    end
  end
end
