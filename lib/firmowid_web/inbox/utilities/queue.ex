defmodule FirmowidWeb.Inbox.Utilities.Queue do
  @moduledoc """
  Builds the inbox: things that need attention, most important first, and this
  month's income and costs.

  Uses policy-scoped domain reads for integration alerts, team approvals,
  personal signatures and settlements, and overdue invoices. Each item links
  to the page where it is dealt with; pending leave requests also offer inline
  decisions.
  """

  use Gettext, backend: Firmowid.Gettext

  alias Firmowid.Analysis
  alias Firmowid.Delegations
  alias Firmowid.Finances
  alias Firmowid.Invoicing
  alias Firmowid.Ksef
  alias Firmowid.Payroll
  alias Firmowid.Timetracker
  alias FirmowidWeb.Delegations.Utilities.Navigation, as: DelegationNavigation
  alias FirmowidWeb.Inbox.Utilities.Navigation
  alias FirmowidWeb.Invoicing.Utilities.Navigation, as: InvoicingNavigation
  alias FirmowidWeb.Management.Utilities.Navigation, as: ManagementNavigation
  alias FirmowidWeb.Settings.Utilities.Navigation, as: SettingsNavigation
  alias FirmowidWeb.Timetracker.Utilities.LeavePresentation

  @type tier :: :urgent | :people | :personal | :books
  @type decision :: %{
          action: atom(),
          record_id: String.t(),
          label: String.t(),
          icon: String.t(),
          show_label?: boolean()
        }
  @type item :: %{
          optional(:decisions) => [decision()],
          optional(:date_range) => String.t(),
          id: String.t(),
          tier: tier(),
          icon: String.t(),
          title: String.t(),
          context: String.t(),
          person: String.t() | nil,
          action: String.t(),
          href: String.t()
        }

  @doc """
  Items of one layer: the company's (`:company`) or the member's own (`:me`).
  Team approvals and integrations are for admins; books are for admins and
  accountants. Every role can see their own actionable items.
  """
  @spec items(:company | :me, Ash.Scope.t(), Date.t()) :: [item()]
  def items(:company, %{actor: %{member: %{role: role}}} = scope, today) when role in [:admin, :accountant] do
    attention_items(scope) ++ overdue_invoice_items(scope, today)
  end

  def items(:me, %{actor: %{member: %{id: member_id}}} = scope, today) do
    contract_items(member_id, scope) ++ personal_delegation_items(member_id, scope, today)
  end

  def items(_layer, _scope, _today), do: []

  @doc """
  The company items that need someone now (urgent and approvals), without the
  books. The sidebar counts these on every page, so they skip the invoice reads.
  """
  @spec attention_items(Ash.Scope.t()) :: [item()]
  def attention_items(%{actor: %{member: %{role: :admin}}} = scope) do
    ksef_items(scope) ++
      bank_items(scope) ++
      leave_items(scope) ++ hours_change_items(scope) ++ company_delegation_items(scope)
  end

  def attention_items(_scope), do: []

  @doc "Groups items by tier, keeping tier order."
  @spec by_tier([item()]) :: [{tier(), [item()]}]
  def by_tier(items) do
    for tier <- [:urgent, :people, :personal, :books],
        tier_items = Enum.filter(items, &(&1.tier == tier)),
        tier_items != [],
        do: {tier, tier_items}
  end

  @doc "Human name of a tier."
  @spec tier_label(tier()) :: String.t()
  def tier_label(:urgent), do: pgettext("inbox tier", "Urgent")
  def tier_label(:people), do: pgettext("inbox tier", "Awaiting approval")
  def tier_label(:personal), do: pgettext("inbox tier", "To do")
  def tier_label(:books), do: pgettext("inbox tier", "Books")

  @doc "One-line explanation of a tier."
  @spec tier_hint(tier()) :: String.t()
  def tier_hint(:urgent), do: gettext("Something is blocked. Deal with it first.")
  def tier_hint(:people), do: gettext("Someone on the team is waiting for your decision.")
  def tier_hint(:personal), do: gettext("Waiting for your signature or settlement.")
  def tier_hint(:books), do: gettext("Overdue invoices with no matched payment.")

  defp ksef_items(scope) do
    case Ksef.connection_status(scope: scope) do
      {:ok, %{status: status}} when status in [:disconnected, :expired] ->
        [
          %{
            id: "ksef",
            tier: :urgent,
            icon: "unplug",
            title:
              if(status == :expired,
                do: gettext("The KSeF connection has expired"),
                else: gettext("KSeF is not connected")
              ),
            context: gettext("Cost invoices do not arrive on their own and sales invoices cannot be sent to KSeF."),
            person: nil,
            action: gettext("Connect"),
            href: Navigation.ksef_settings_path()
          }
        ]

      {:ok, _connected} ->
        []
    end
  end

  defp bank_items(scope) do
    [scope: scope, load: [:broken?, :latest_successful_sync_at, :requisition]]
    |> Finances.list_bank_accounts!()
    |> Enum.filter(&sync_stopped?/1)
    |> Enum.map(fn account ->
      %{
        id: "bank-#{account.id}",
        tier: :urgent,
        icon: "landmark",
        title:
          gettext("%{account}: synchronization stopped",
            account: account.name || account.institution_name
          ),
        context: last_sync_context(account.latest_successful_sync_at),
        person: nil,
        action: gettext("Renew consent"),
        href: Navigation.bank_settings_path()
      }
    end)
  end

  # The same rule as the broken bank account status in the company settings: an
  # expired or rejected consent stops the sync without a failed sync attempt.
  defp sync_stopped?(%{institution_name: "Manual"}), do: false
  defp sync_stopped?(%{gocardless_id: nil}), do: false

  defp sync_stopped?(%{requisition: %{status: status}}) when status in [:rejected, :expired], do: true

  defp sync_stopped?(account), do: account.broken? == true

  defp last_sync_context(nil), do: gettext("No transactions have been fetched from this account yet.")

  defp last_sync_context(at) do
    gettext("Transactions were last fetched on %{date}.", date: Calendar.strftime(at, "%d.%m"))
  end

  defp leave_items(scope) do
    %{status: :pending}
    |> Timetracker.list_leave_requests!(scope: scope, load: [member: [:display_name]])
    |> Enum.map(fn request ->
      days = Date.diff(request.ends_on, request.starts_on) + 1

      %{
        id: "leave-#{request.id}",
        tier: :people,
        icon: "calendar-days",
        title: gettext("Leave request"),
        date_range: "#{Calendar.strftime(request.starts_on, "%d.%m")}–#{Calendar.strftime(request.ends_on, "%d.%m")}",
        context:
          Enum.join(
            [
              LeavePresentation.reason_label(request.reason),
              ngettext("%{count} calendar day", "%{count} calendar days", days)
            ],
            " · "
          ),
        person: request.member.display_name,
        action: gettext("Review"),
        href: Navigation.employee_leaves_path(request.member_id),
        decisions: leave_decisions(request)
      }
    end)
  end

  defp leave_decisions(request) do
    accept = %{
      action: :accept_leave_request,
      record_id: request.id,
      label: pgettext("inbox decision", "Accept"),
      icon: "check",
      show_label?: true
    }

    decline = %{
      action: :decline_leave_request,
      record_id: request.id,
      label: gettext("Reject"),
      icon: "x",
      show_label?: false
    }

    if request.category == :leave, do: [accept, decline], else: [accept]
  end

  defp contract_items(member_id, scope) do
    case Payroll.load_pending_contract(member_id, scope: scope) do
      {:ok, nil} ->
        []

      {:ok, contract} ->
        [
          %{
            id: "contract-#{contract.id}",
            tier: :personal,
            icon: "file-signature",
            title: gettext("Your employment contract is waiting for your signature"),
            context: gettext("Download the contract, sign it and upload the signed document."),
            person: nil,
            action: gettext("Sign"),
            href: SettingsNavigation.canonical_path(:profile)
          }
        ]
    end
  end

  defp hours_change_items(scope) do
    %{pending_change?: true}
    |> Timetracker.list_hours_records!(scope: scope, load: [member: [:display_name]])
    |> Enum.map(fn record ->
      month = Date.new!(record.year, record.month, 1)

      %{
        id: "hours-change-#{record.id}",
        tier: :people,
        icon: "clipboard-list",
        title: gettext("Timesheet change request, %{month}", month: Calendar.strftime(month, "%m.%Y")),
        context: record.change_request_reason,
        person: record.member.display_name,
        action: gettext("Review"),
        href: ManagementNavigation.employee_path(record.member.user_id, %{miesiac: month})
      }
    end)
  end

  defp company_delegation_items(scope) do
    %{statuses: [:pending, :submitted]}
    |> Delegations.list_delegations!(scope: scope, load: [member: [:display_name]])
    |> Enum.map(fn trip ->
      %{
        id: "delegation-#{trip.id}",
        tier: :people,
        icon: "plane",
        title: delegation_title(trip),
        context: trip.title,
        person: trip.member.display_name,
        action: gettext("Review"),
        href: ManagementNavigation.employee_delegation_path(trip.member.user_id, trip.reference)
      }
    end)
  end

  defp personal_delegation_items(member_id, scope, today) do
    finished =
      Delegations.list_delegations!(
        %{member_id: member_id, statuses: [:in_progress], ended_before: today},
        scope: scope
      )

    unsigned =
      Delegations.list_delegations!(%{member_id: member_id, statuses: [:awaiting_signature]},
        scope: scope
      )

    Enum.map(finished ++ unsigned, fn trip ->
      %{
        id: "delegation-#{trip.id}",
        tier: :personal,
        icon: "plane",
        title: delegation_title(trip),
        context: trip.title,
        person: nil,
        action: if(trip.status == :awaiting_signature, do: gettext("Sign"), else: gettext("Settle")),
        href: DelegationNavigation.show_path(trip.reference)
      }
    end)
  end

  defp delegation_title(%{status: :pending}), do: gettext("Business trip order awaiting approval")

  defp delegation_title(%{status: :submitted}), do: gettext("Business trip settlement awaiting review")

  defp delegation_title(%{status: :in_progress}), do: gettext("Your business trip needs settlement")

  defp delegation_title(%{status: :awaiting_signature}), do: gettext("Your business trip settlement needs a signature")

  defp overdue_invoice_items(scope, today) do
    sales =
      Invoicing.list_sales_invoices!(
        %{overdue_on: today, kind: :vat, submission: :confirmed},
        scope: scope,
        load: [:effective_due_date, :effective_amount, :buyer_display_name_label]
      )

    costs =
      Invoicing.list_cost_invoices!(
        %{overdue_on: today, merge_corrections: true},
        scope: scope,
        load: [
          :effective_due_date,
          :effective_amount,
          :effective_seller_display_name,
          :effective_seller
        ]
      )

    Enum.sort_by(
      Enum.map(sales, &overdue_invoice_item(&1, :sales)) ++
        Enum.map(costs, &overdue_invoice_item(&1, :cost)),
      & &1.due_date,
      Date
    )
  end

  defp overdue_invoice_item(invoice, side) do
    %{
      id: "overdue-#{side}-#{invoice.id}",
      tier: :books,
      side: side,
      due_date: invoice.effective_due_date,
      icon: "file-clock",
      title: overdue_invoice_title(invoice, side),
      context:
        gettext("%{amount} · due %{date}",
          amount: Money.to_string!(Money.abs(invoice.effective_amount)),
          date: Calendar.strftime(invoice.effective_due_date, "%d.%m.%Y")
        ),
      person: counterparty_name(invoice, side),
      action: gettext("Review"),
      href:
        if(side == :sales,
          do: InvoicingNavigation.sales_invoice_show_path(invoice),
          else: InvoicingNavigation.cost_invoice_show_path(invoice)
        )
    }
  end

  defp counterparty_name(invoice, :sales), do: invoice.buyer_display_name_label

  defp counterparty_name(invoice, :cost), do: invoice.effective_seller_display_name || invoice.effective_seller

  defp overdue_invoice_title(invoice, :sales),
    do: gettext("Overdue sales invoice %{number}", number: invoice.invoice_number)

  defp overdue_invoice_title(invoice, :cost),
    do: gettext("Overdue cost invoice %{number}", number: invoice.invoice_identifier || invoice.id)

  @doc """
  Income and costs from the start of `today`'s month for admins and
  accountants, who see the company's finances; nothing for others.
  """
  @spec month(Ash.Scope.t(), Date.t()) :: [
          %{label: String.t(), value: String.t(), side: :sales | :cost}
        ]
  def month(%{actor: %{member: %{role: role}}} = scope, today) when role in [:admin, :accountant] do
    totals = Analysis.get_organization_totals(Date.beginning_of_month(today), today, [], scope)

    [
      %{label: gettext("Income"), value: pln(totals.total_income), side: :sales},
      %{label: gettext("Costs"), value: pln(totals.total_expenses), side: :cost}
    ]
  end

  def month(_scope, _today), do: []

  defp pln(amount), do: Money.to_string!(Money.new(:PLN, Decimal.abs(amount)), fractional_digits: 0)
end
