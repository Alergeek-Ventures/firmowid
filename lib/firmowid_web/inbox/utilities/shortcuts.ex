defmodule FirmowidWeb.Inbox.Utilities.Shortcuts do
  @moduledoc """
  The actions offered as buttons under the company inbox: what the organization
  does most often comes first.

  "Most often" is how many records each action created in the last
  `window_days/0` days, counted through policy-scoped reads. An action the
  organization did not use in that time is left out, unless fewer than four
  were used: then the unused ones fill the row in the order of the list below,
  which is also what a new company sees. A member sees only the actions their
  role may perform.
  """

  use Gettext, backend: Firmowid.Gettext

  alias Firmowid.Core
  alias Firmowid.Core.Organization
  alias Firmowid.Core.OrganizationInvite
  alias Firmowid.Invoicing
  alias Firmowid.Invoicing.CostInvoice
  alias Firmowid.Invoicing.Counterparty
  alias Firmowid.Invoicing.SalesInvoice
  alias Firmowid.Timetracker
  alias Firmowid.Timetracker.Project
  alias FirmowidWeb.Invoicing.Utilities.Navigation, as: InvoicingNavigation
  alias FirmowidWeb.Management.Utilities.Navigation, as: ManagementNavigation

  require Ash.Query

  @window_days 90
  @filled_to 4
  @shown 6

  @type shortcut :: %{
          id: atom(),
          label: String.t(),
          icon: String.t(),
          target: {:navigate, String.t()} | :upload
        }

  @doc "How many days of the organization's activity decide the order."
  @spec window_days() :: pos_integer()
  def window_days, do: @window_days

  @doc """
  Four to six actions the member may perform, the organization's most
  frequent first; fewer when the role allows fewer.
  """
  @spec for_company(Ash.Scope.t(), Organization.t(), DateTime.t()) :: [shortcut()]
  def for_company(%{actor: actor} = scope, %Organization{} = organization, now) do
    from = DateTime.shift(now, day: -@window_days)

    {used, unused} =
      organization
      |> candidates()
      |> Enum.filter(fn {_shortcut, permission, _uses} -> Ash.can?(permission, actor) end)
      |> Enum.map(fn {shortcut, _permission, uses} -> {shortcut, uses.(scope, from)} end)
      |> Enum.sort_by(fn {_shortcut, uses} -> uses end, :desc)
      |> Enum.split_with(fn {_shortcut, uses} -> uses > 0 end)

    used
    |> Enum.concat(Enum.take(unused, max(@filled_to - length(used), 0)))
    |> Enum.take(@shown)
    |> Enum.map(fn {shortcut, _uses} -> shortcut end)
  end

  # Each action with the permission it needs and how often the organization
  # used it since `from`. Projects exist only where time is billed by the hour.
  defp candidates(organization) do
    Enum.reject(
      [
        {%{
           id: :issue_sales_invoice,
           label: gettext("Issue invoice"),
           icon: "file-chart-column",
           target: {:navigate, InvoicingNavigation.sales_invoice_creator_path()}
         }, {SalesInvoice, :draft}, &issued_sales_invoices/2},
        {%{
           id: :upload_cost_invoice,
           label: gettext("Add an invoice from outside KSeF"),
           icon: "cloud-upload",
           target: :upload
         }, {CostInvoice, :create}, &uploaded_cost_invoices/2},
        {%{
           id: :add_counterparty,
           label: gettext("Add counterparty"),
           icon: "building-2",
           target: {:navigate, ManagementNavigation.counterparty_new_path()}
         }, {Counterparty, :create}, &added_counterparties/2},
        organization.bills_hourly &&
          {%{
             id: :add_project,
             label: gettext("Add project"),
             icon: "folder-kanban",
             target: {:navigate, ManagementNavigation.project_new_path()}
           }, {Project, :create}, &added_projects/2},
        {%{
           id: :invite_employee,
           label: gettext("Invite an employee"),
           icon: "user",
           target: {:navigate, ManagementNavigation.employees_path(:index)}
         }, {OrganizationInvite, :create}, &sent_invites/2}
      ],
      &(&1 == false)
    )
  end

  defp issued_sales_invoices(scope, from) do
    %{inserted_from: from}
    |> Invoicing.query_to_list_sales_invoices(scope: scope)
    |> Ash.count!(scope: scope)
  end

  defp uploaded_cost_invoices(scope, from) do
    %{source: :manual_import, inserted_from: from}
    |> Invoicing.query_to_list_cost_invoices(scope: scope)
    |> Ash.count!(scope: scope)
  end

  defp added_counterparties(scope, from) do
    %{status: :all}
    |> Invoicing.query_to_list_counterparties(scope: scope)
    |> count_inserted_since(from, scope)
  end

  defp added_projects(scope, from) do
    %{}
    |> Timetracker.query_to_list_projects(scope: scope)
    |> count_inserted_since(from, scope)
  end

  defp sent_invites(scope, from) do
    [scope: scope]
    |> Core.query_to_list_invites()
    |> count_inserted_since(from, scope)
  end

  defp count_inserted_since(query, from, scope) do
    query
    |> Ash.Query.filter(inserted_at >= ^from)
    |> Ash.count!(scope: scope)
  end
end
