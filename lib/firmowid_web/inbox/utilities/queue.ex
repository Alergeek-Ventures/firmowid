defmodule FirmowidWeb.Inbox.Utilities.Queue do
  @moduledoc """
  Builds the inbox: things that need attention, most important first, and this
  month's income and costs.

  Only signals the app already knows are shown (KSeF connection, broken bank
  syncs, pending leave requests). Each item links to the page where it is dealt
  with; decisions are not made in the inbox yet.
  """

  use Gettext, backend: Firmowid.Gettext

  alias Firmowid.Analysis
  alias Firmowid.Finances
  alias Firmowid.Ksef
  alias Firmowid.Timetracker
  alias FirmowidWeb.Inbox.Utilities.Navigation

  @type tier :: :urgent | :people
  @type item :: %{
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
  Company items are only collected for admins, who can deal with them.
  """
  @spec items(:company | :me, Ash.Scope.t()) :: [item()]
  def items(:company, %{actor: %{member: %{role: :admin}}} = scope) do
    ksef_items(scope) ++ bank_items(scope) ++ leave_items(scope)
  end

  def items(_layer, _scope), do: []

  @doc "Groups items by tier, keeping tier order."
  @spec by_tier([item()]) :: [{tier(), [item()]}]
  def by_tier(items) do
    for tier <- [:urgent, :people],
        tier_items = Enum.filter(items, &(&1.tier == tier)),
        tier_items != [],
        do: {tier, tier_items}
  end

  @doc "Human name of a tier."
  @spec tier_label(tier()) :: String.t()
  def tier_label(:urgent), do: pgettext("inbox tier", "Urgent")
  def tier_label(:people), do: pgettext("inbox tier", "Awaiting approval")

  @doc "One-line explanation of a tier."
  @spec tier_hint(tier()) :: String.t()
  def tier_hint(:urgent), do: gettext("Something is blocked. Deal with it first.")
  def tier_hint(:people), do: gettext("Someone on the team is waiting for your decision.")

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
        title:
          gettext("Leave request, %{from}–%{to}",
            from: Calendar.strftime(request.starts_on, "%d.%m"),
            to: Calendar.strftime(request.ends_on, "%d.%m")
          ),
        context: ngettext("%{count} calendar day", "%{count} calendar days", days),
        person: request.member.display_name,
        action: gettext("Review"),
        href: Navigation.employee_leaves_path(request.member_id)
      }
    end)
  end

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
