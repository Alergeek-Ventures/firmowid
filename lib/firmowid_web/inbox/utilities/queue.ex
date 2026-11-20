defmodule FirmowidWeb.Inbox.Utilities.Queue do
  @moduledoc """
  Builds the inbox: things that need attention, most important first, and this
  month's income and costs.

  Uses policy-scoped domain reads for integration alerts, counterparty EU VAT
  numbers that the periodic check rejected, company details that contradict the
  registers, team approvals, personal signatures and settlements, overdue
  invoices and sales invoices the KSeF import skipped; usage above the billing
  plan comes from `Firmowid.Billing.PlanLimits`. Each item links to the page
  where it is dealt with; pending leave requests also offer inline decisions.
  Items for information only (`:info`) ask nothing of the company and link
  nowhere; they follow the urgent ones, as they are rare and worth noticing.

  An item's id names its record and the stage or period of its problem, as the
  company puts items aside by id (`Firmowid.Core.InboxSnooze`): putting one stage
  aside must not hide the next one, such as a trip's settlement after its order.
  """

  use Gettext, backend: Firmowid.Gettext

  alias Firmowid.Analysis
  alias Firmowid.Billing.PlanCatalog
  alias Firmowid.Billing.PlanLimits
  alias Firmowid.Core
  alias Firmowid.Core.InboxSnooze
  alias Firmowid.Core.Organization
  alias Firmowid.Core.Organization.NipCheck
  alias Firmowid.Delegations
  alias Firmowid.Finances
  alias Firmowid.Invoicing
  alias Firmowid.Ksef
  alias Firmowid.Payroll
  alias Firmowid.Taxes
  alias Firmowid.Timetracker
  alias FirmowidWeb.Billing.Utilities.Navigation, as: BillingNavigation
  alias FirmowidWeb.Billing.Utilities.Worksheet
  alias FirmowidWeb.Delegations.Utilities.DelegationPresentation
  alias FirmowidWeb.Delegations.Utilities.Navigation, as: DelegationNavigation
  alias FirmowidWeb.Inbox.Utilities.Navigation
  alias FirmowidWeb.Invoicing.Utilities.Navigation, as: InvoicingNavigation
  alias FirmowidWeb.Management.Utilities.Navigation, as: ManagementNavigation
  alias FirmowidWeb.Settings.Utilities.Navigation, as: SettingsNavigation
  alias FirmowidWeb.Settings.Utilities.RegisterCheck
  alias FirmowidWeb.Timetracker.Utilities.LeavePresentation

  @type tier :: :urgent | :people | :personal | :books | :info
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
          optional(:days_late) => pos_integer(),
          optional(:amount) => String.t(),
          optional(:action) => String.t(),
          optional(:href) => String.t(),
          id: String.t(),
          tier: tier(),
          icon: String.t(),
          title: String.t(),
          context: String.t(),
          person: String.t() | nil
        }

  @doc """
  Items of one layer: the company's (`:company`) or the member's own (`:me`).
  Team approvals and integrations are for admins; books are for admins and
  accountants. Every role can see their own actionable items.

  `opts` carry the interface's feature flags, see `attention_items/3`.
  """
  @spec items(:company | :me, Ash.Scope.t(), Organization.t(), Date.t(), keyword()) :: [item()]
  def items(layer, scope, organization, today, opts \\ [])

  def items(:company, %{actor: %{member: %{role: role}}} = scope, organization, today, opts)
      when role in [:admin, :accountant] do
    attention_items(scope, organization, opts) ++
      overdue_invoice_items(scope, today) ++ skipped_ksef_invoice_items(scope)
  end

  def items(:me, %{actor: %{member: %{id: member_id}}} = scope, _organization, today, _opts) do
    contract_items(member_id, scope) ++ personal_delegation_items(member_id, scope, today)
  end

  def items(_layer, _scope, _organization, _today, _opts), do: []

  @doc """
  The company items that need someone now (urgent and approvals), without the
  books. The sidebar counts these on every page, so they skip the invoice reads
  and take the organization the page already loaded.

  With `taxes?: true` (the `:taxes` feature flag) a missing tax profile, or tax
  settings that new transfers contradict, are listed too.
  """
  @spec attention_items(Ash.Scope.t(), Organization.t(), keyword()) :: [item()]
  def attention_items(scope, organization, opts \\ [])

  def attention_items(%{actor: %{member: %{role: :admin}}} = scope, organization, opts) do
    plan_limit_items(organization) ++
      register_items(organization) ++
      ksef_items(scope) ++
      tax_profile_items(scope, organization, Keyword.get(opts, :taxes?, false)) ++
      bank_items(scope) ++
      vat_id_items(scope) ++
      leave_items(scope) ++ hours_change_items(scope) ++ company_delegation_items(scope)
  end

  def attention_items(_scope, _organization, _opts), do: []

  @doc """
  Splits items into those to show and those the company put aside
  (`Firmowid.Core.InboxSnooze`), each of the latter with its snooze.
  """
  @spec split_put_aside([item()], Ash.Scope.t()) :: {[item()], [{item(), InboxSnooze.t()}]}
  def split_put_aside([], _scope), do: {[], []}

  def split_put_aside(items, scope) do
    snoozes = Map.new(Core.list_inbox_snoozes!(scope: scope), &{&1.item_id, &1})

    {put_aside, shown} = Enum.split_with(items, &Map.has_key?(snoozes, &1.id))
    {shown, Enum.map(put_aside, &{&1, Map.fetch!(snoozes, &1.id)})}
  end

  @doc "Groups items by tier, keeping tier order."
  @spec by_tier([item()]) :: [{tier(), [item()]}]
  def by_tier(items) do
    for tier <- [:urgent, :info, :people, :personal, :books],
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
  def tier_label(:info), do: pgettext("inbox tier", "KSeF sync")

  @doc "One-line explanation of a tier."
  @spec tier_hint(tier()) :: String.t()
  def tier_hint(:urgent), do: gettext("Something needs your urgent attention.")
  def tier_hint(:people), do: gettext("Someone on the team is waiting for your decision.")
  def tier_hint(:personal), do: gettext("Things waiting for you.")
  def tier_hint(:books), do: gettext("Overdue invoices with no matched payment.")
  def tier_hint(:info), do: gettext("These invoices are already in KSeF. Nothing to do.")

  # Usage is counted only while a decision day is set. Nothing once the usage
  # fits the plan again, until the scheduled check ends the decision.
  defp plan_limit_items(%Organization{plan_limit_decision_on: nil}), do: []

  defp plan_limit_items(%Organization{billing_plan: plan} = organization) do
    usage = PlanLimits.usage(organization)

    case PlanCatalog.exceeded(usage, plan) do
      [] ->
        []

      [limited | _others] ->
        [
          %{
            id: "plan-limit-#{organization.plan_limit_decision_on}",
            tier: :urgent,
            icon: "gauge",
            title: gettext("Above the %{plan} plan", plan: Worksheet.plan_label(plan)),
            context:
              gettext("%{label}: %{count}, the plan includes %{limit}",
                label: Worksheet.limited_label(limited),
                count: usage[limited],
                limit: PlanCatalog.plan!(plan).limits[limited]
              ),
            person: nil,
            action: gettext("Choose now"),
            href: BillingNavigation.plan_limit_path()
          }
        ]
    end
  end

  defp ksef_items(scope) do
    case Ksef.connection_status(scope: scope) do
      {:ok, %{status: status}} when status in [:disconnected, :expired] ->
        [
          %{
            id: "ksef-#{status}",
            tier: :urgent,
            icon: "unplug",
            title:
              if(status == :expired,
                do: gettext("The KSeF connection has expired"),
                else: gettext("KSeF is not connected")
              ),
            context:
              gettext(
                "Until it is connected, you cannot issue sales invoices, and cost invoices do not arrive on their own."
              ),
            person: nil,
            action: gettext("Connect"),
            href: SettingsNavigation.canonical_path(:ksef)
          }
        ]

      {:ok, _connected} ->
        []
    end
  end

  # Payments to the tax office and ZUS are calculated from the legal form and the
  # current year's tax settings, so either one missing blocks them. Synced transfers
  # that contradict the saved settings wait for a confirmation.
  defp tax_profile_items(_scope, _organization, false = _taxes?), do: []

  defp tax_profile_items(scope, organization, true = _taxes?) do
    # The year turns at Polish midnight, as in the taxes card.
    year = Firmowid.LocalDate.today().year

    tax_year =
      organization.legal_form &&
        List.first(Taxes.list_tax_years!(%{year: year}, scope: scope, load: [:partners]))

    cond do
      is_nil(tax_year) ->
        [
          tax_profile_item(
            "tax-profile-#{year}-missing",
            gettext("Fill in taxes and ZUS for %{year}", year: year),
            gettext(
              "Without the legal form and how the company is taxed we cannot calculate the payments to the tax office and ZUS."
            ),
            gettext("Fill in")
          )
        ]

      year
      |> Taxes.suggest_tax_settings!(scope: scope)
      |> Taxes.pending_suggestions(tax_year, organization)
      |> Enum.any?() ->
        [
          tax_profile_item(
            "tax-profile-#{year}-suggestions",
            gettext("Confirm taxes and ZUS for %{year}", year: year),
            gettext("New transactions suggest different settings than the saved ones."),
            gettext("Check")
          )
        ]

      true ->
        []
    end
  end

  defp tax_profile_item(id, title, context, action) do
    %{
      id: id,
      tier: :urgent,
      icon: "clipboard-list",
      title: title,
      context: context,
      person: nil,
      action: action,
      href: SettingsNavigation.canonical_path(:organization) <> "#podatki"
    }
  end

  # The id names the contradiction, so a different one counts as a new item.
  defp register_items(organization) do
    case NipCheck.mismatch(organization) do
      nil ->
        []

      mismatch ->
        [
          %{
            id: "register-#{mismatch}",
            tier: :urgent,
            icon: "id-card",
            title: gettext("Company details differ from the registers"),
            context: RegisterCheck.problem(organization),
            person: nil,
            action: gettext("Check the company details"),
            # Lands on the message under the detail it concerns.
            href: SettingsNavigation.canonical_path(:organization) <> "#rejestry"
          }
        ]
    end
  end

  defp vat_id_items(scope) do
    %{vat_id_statuses: [:invalid, :inactive, :closed, :unknown]}
    |> Invoicing.list_counterparties!(scope: scope, load: [:display_label])
    |> Enum.map(fn counterparty ->
      %{
        id: "vat-id-#{counterparty.id}-#{counterparty.vat_id_status}",
        tier: :urgent,
        icon: "id-card",
        title: vat_id_title(counterparty),
        context: vat_id_context(counterparty),
        person: nil,
        action: gettext("Check the counterparty"),
        href: ManagementNavigation.counterparty_edit_path(counterparty.id)
      }
    end)
  end

  defp vat_id_title(%{vat_id_status: status} = counterparty) when status in [:closed, :unknown],
    do: gettext("%{counterparty}: NIP to check", counterparty: counterparty.display_label)

  defp vat_id_title(counterparty),
    do: gettext("%{counterparty}: EU VAT number to check", counterparty: counterparty.display_label)

  defp vat_id_context(%{vat_id_status: :closed, tax_id: tax_id, vat_id_checked_at: checked_at}),
    do:
      gettext("CEIDG showed the business with NIP %{number} as deregistered on %{date}.",
        number: tax_id,
        date: Calendar.strftime(checked_at, "%d.%m")
      )

  defp vat_id_context(%{vat_id_status: :unknown, tax_id: tax_id}),
    do: gettext("No register knows NIP %{number}.", number: tax_id)

  defp vat_id_context(%{vat_id_status: :invalid, tax_id: tax_id}),
    do: gettext("%{number} does not match the VAT number format of its country.", number: tax_id)

  defp vat_id_context(%{vat_id_status: :inactive, tax_id: tax_id, vat_id_checked_at: checked_at}),
    do:
      gettext("VIES did not confirm %{number} on %{date}.", number: tax_id, date: Calendar.strftime(checked_at, "%d.%m"))

  defp bank_items(scope) do
    [scope: scope, query: [filter: [sync_stopped?: true]], load: [:latest_successful_sync_at]]
    |> Finances.list_bank_accounts!()
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
        href: SettingsNavigation.canonical_path(:bank_accounts)
      }
    end)
  end

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
        href: Navigation.employee_leaves_path(request.member.user_id),
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
        id: "delegation-#{trip.id}-#{trip.status}",
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

    # The trip's dates lead the meta line, where company items name the person.
    Enum.map(finished ++ unsigned, fn trip ->
      %{
        id: "delegation-#{trip.id}-#{trip.status}",
        tier: :personal,
        icon: "plane",
        title: gettext("Business trip settlement: %{title}", title: trip.title),
        context: settlement_step(trip),
        person: DelegationPresentation.format_range(trip.start_date, trip.end_date),
        action: if(trip.status == :awaiting_signature, do: gettext("Sign"), else: gettext("Settle")),
        href: DelegationNavigation.show_path(trip.reference)
      }
    end)
  end

  # A business trip is settled within 14 days of its end (§ 5 of the business
  # travel regulation under art. 77⁵ of the Labour Code).
  defp settlement_step(%{status: :awaiting_signature}), do: gettext("waiting for your signature")

  defp settlement_step(trip) do
    gettext("settle by %{date}",
      date: trip.end_date |> Date.add(14) |> Calendar.strftime("%d.%m")
    )
  end

  defp delegation_title(%{status: :pending}), do: gettext("Business trip order awaiting approval")

  defp delegation_title(%{status: :submitted}), do: gettext("Business trip settlement awaiting review")

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
      Enum.map(sales, &overdue_invoice_item(&1, :sales, today)) ++
        Enum.map(costs, &overdue_invoice_item(&1, :cost, today)),
      & &1.due_date,
      Date
    )
  end

  defp overdue_invoice_item(invoice, side, today) do
    %{
      id: "overdue-#{side}-#{invoice.id}",
      tier: :books,
      side: side,
      due_date: invoice.effective_due_date,
      days_late: Date.diff(today, invoice.effective_due_date),
      icon: "file-chart-column",
      title: overdue_invoice_title(invoice, side),
      amount: Money.to_string!(Money.abs(invoice.effective_amount)),
      context: gettext("due %{date}", date: Calendar.strftime(invoice.effective_due_date, "%d.%m.%Y")),
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

  # A sales invoice issued outside Firmowid that the KSeF import could not record yet
  # (`Firmowid.Invoicing.SkippedKsefSalesInvoice`). Engineers get the cause and the
  # item goes away once a later import records the invoice, so it only informs.
  defp skipped_ksef_invoice_items(scope) do
    [scope: scope]
    |> Invoicing.list_skipped_ksef_sales_invoices!()
    |> Enum.map(fn invoice ->
      %{
        id: "ksef-skipped-#{invoice.id}",
        tier: :info,
        icon: "file-clock",
        # Who it was issued to and for how much tell the company which invoice it is.
        title:
          [
            invoice.buyer_name,
            invoice.currency |> Money.new(invoice.gross_total) |> Money.to_string!()
          ]
          |> Enum.reject(&is_nil/1)
          |> Enum.join(" · "),
        context:
          gettext("Issued %{date} · sync in progress",
            date: Calendar.strftime(invoice.issue_date, "%d.%m.%Y")
          ),
        person: nil
      }
    end)
  end

  @doc """
  Income and costs of `today`'s whole month, the same totals the analysis
  shows for it, for admins and accountants, who see the company's finances;
  nothing for others.
  """
  @spec month(Ash.Scope.t(), Date.t()) :: [
          %{label: String.t(), value: String.t(), side: :sales | :cost}
        ]
  def month(%{actor: %{member: %{role: role}}} = scope, today) when role in [:admin, :accountant] do
    totals =
      Analysis.get_organization_totals(
        Date.beginning_of_month(today),
        Date.end_of_month(today),
        [],
        scope
      )

    [
      %{label: gettext("Income"), value: pln(totals.total_income), side: :sales},
      %{label: gettext("Costs"), value: pln(totals.total_expenses), side: :cost}
    ]
  end

  def month(_scope, _today), do: []

  defp pln(amount), do: Money.to_string!(Money.new(:PLN, Decimal.abs(amount)), fractional_digits: 0)
end
