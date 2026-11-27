defmodule FirmowidWeb.Inbox.Utilities.Navigation do
  @moduledoc """
  Flat list of places in the app for the sidebar, split into the company layer
  and the member's own layer, plus the inbox URLs.
  """

  use FirmowidWeb, :verified_routes
  use Gettext, backend: Firmowid.Gettext

  alias Firmowid.Core.UserRole
  alias FirmowidWeb.Assistant.Utilities.Navigation, as: AssistantNavigation
  alias FirmowidWeb.Invoicing.Utilities.Navigation, as: InvoicingNavigation
  alias FirmowidWeb.Settings.Utilities.Navigation, as: SettingsNavigation

  @type layer :: :main | :company | :me
  @type destination :: %{
          optional(:beta?) => true,
          id: atom(),
          layer: layer(),
          label: String.t(),
          icon: String.t(),
          path: String.t(),
          roles: [UserRole.t()]
        }

  @managers [:admin, :invoicing, :accountant]

  @doc "Inbox of one layer: the company's (`:company`) or the member's own (`:me`)."
  @spec inbox_path(:company | :me) :: String.t()
  def inbox_path(:company), do: ~p"/skrzynka"
  def inbox_path(:me), do: ~p"/skrzynka?#{[warstwa: "ty"]}"

  @doc "Parses the `warstwa` query value of the inbox."
  @spec parse_layer(String.t() | nil) :: :company | :me
  def parse_layer("ty"), do: :me
  def parse_layer(_value), do: :company

  @doc "Where an admin reviews the leave requests of the employee with `user_id`."
  @spec employee_leaves_path(String.t()) :: String.t()
  def employee_leaves_path(user_id), do: ~p"/zarzadzanie/pracownicy/#{user_id}/urlopy"

  @doc """
  The destinations a member with `role` may open. `analysis?` and
  `delegations?` reflect the analysis dashboard and business trips flags;
  `owner?` controls subscription visibility; `time_tracking?` is off for a
  company that does not bill by the hour, which hides time tracking and projects.
  """
  @spec for_role(UserRole.t(), boolean(), boolean(), boolean(), boolean()) :: [destination()]
  def for_role(role, analysis?, owner?, delegations?, time_tracking?) do
    Enum.filter(all(), fn destination ->
      role in destination.roles and (destination.id != :analysis or analysis?) and
        (destination.id != :subscription or owner?) and
        (destination.id != :delegations or delegations?) and
        (destination.id not in [:timetracker, :projects] or time_tracking?)
    end)
  end

  @doc "Returns the destinations of one layer."
  @spec in_layer([destination()], layer()) :: [destination()]
  def in_layer(destinations, layer), do: Enum.filter(destinations, &(&1.layer == layer))

  @doc """
  The destination the URI belongs to: the longest matching path whose query
  parameters (e.g. `filtr` of invoicing) are all present in the URI.
  """
  @spec current([destination()], URI.t()) :: destination() | nil
  def current(destinations, %URI{} = uri) do
    query = URI.decode_query(uri.query || "")

    destinations
    |> Enum.filter(fn destination ->
      target = URI.parse(destination.path)

      (uri.path == target.path or String.starts_with?(uri.path, target.path <> "/")) and
        Enum.all?(URI.decode_query(target.query || ""), fn {key, value} -> query[key] == value end)
    end)
    |> Enum.max_by(&String.length(&1.path), fn -> nil end)
  end

  defp all do
    [
      %{
        id: :inbox,
        layer: :main,
        label: pgettext("sidebar", "Inbox"),
        icon: "skrzynka",
        path: ~p"/skrzynka",
        roles: UserRole.roles()
      },
      %{
        id: :timetracker,
        layer: :main,
        label: pgettext("main navigation", "Time tracking"),
        icon: "czasosledz",
        path: ~p"/czasosledz",
        roles: UserRole.roles()
      },
      %{
        id: :invoices,
        layer: :company,
        label: gettext("Invoices"),
        icon: "faktury",
        path: InvoicingNavigation.invoices_list_path(),
        roles: @managers
      },
      %{
        id: :transactions,
        layer: :company,
        label: gettext("Transactions"),
        icon: "transakcje",
        path: InvoicingNavigation.transactions_list_path(),
        roles: @managers
      },
      %{
        id: :assistant,
        layer: :company,
        label: pgettext("sidebar", "Assistant"),
        icon: "asystent",
        path: AssistantNavigation.page_path(),
        roles: @managers
      },
      %{
        id: :team,
        layer: :company,
        label: pgettext("sidebar", "Team"),
        icon: "zespol",
        path: ~p"/zarzadzanie/pracownicy",
        roles: [:admin]
      },
      %{
        id: :counterparties,
        layer: :company,
        label: pgettext("management navigation", "Counterparties"),
        icon: "company",
        path: ~p"/zarzadzanie/kontrahenci",
        roles: [:admin]
      },
      %{
        id: :projects,
        layer: :company,
        label: pgettext("management navigation", "Projects"),
        icon: "projekty",
        path: ~p"/zarzadzanie/projekty",
        roles: [:admin]
      },
      %{
        id: :analysis,
        layer: :company,
        label: pgettext("main navigation", "Analysis"),
        icon: "analiza",
        path: ~p"/analiza",
        roles: [:admin],
        beta?: true
      },
      %{
        id: :company_settings,
        layer: :company,
        label: SettingsNavigation.page_title(:organization),
        icon: "dane_firmy",
        path: SettingsNavigation.canonical_path(:organization),
        roles: [:admin]
      },
      %{
        id: :ksef,
        layer: :company,
        label: SettingsNavigation.page_title(:ksef),
        icon: "unplug",
        path: SettingsNavigation.canonical_path(:ksef),
        roles: [:admin]
      },
      %{
        id: :bank_accounts,
        layer: :company,
        label: SettingsNavigation.page_title(:bank_accounts),
        icon: "konta_bankowe",
        path: SettingsNavigation.canonical_path(:bank_accounts),
        roles: [:admin]
      },
      %{
        id: :integrations,
        layer: :company,
        label: SettingsNavigation.page_title(:integrations),
        icon: "boxes_layout",
        path: SettingsNavigation.canonical_path(:integrations),
        roles: UserRole.roles()
      },
      %{
        id: :subscription,
        layer: :company,
        label: SettingsNavigation.page_title(:subscription),
        icon: "card",
        path: SettingsNavigation.canonical_path(:subscription),
        roles: UserRole.roles()
      },
      %{
        id: :hours_record,
        layer: :me,
        label: pgettext("sidebar", "My timesheet"),
        icon: "ewidencja",
        path: ~p"/czasosledz/ewidencja",
        roles: UserRole.roles()
      },
      %{
        id: :profile,
        layer: :me,
        label: SettingsNavigation.page_title(:profile),
        icon: "dane_kadrowe",
        path: SettingsNavigation.canonical_path(:profile),
        roles: UserRole.roles()
      },
      %{
        id: :documents,
        layer: :me,
        label: SettingsNavigation.page_title(:documents),
        icon: "dokumenty",
        path: SettingsNavigation.canonical_path(:documents),
        roles: UserRole.roles()
      },
      %{
        id: :delegations,
        layer: :me,
        label: SettingsNavigation.page_title(:delegations),
        icon: "delegacje",
        path: SettingsNavigation.canonical_path(:delegations),
        roles: UserRole.roles()
      },
      %{
        id: :leaves,
        layer: :me,
        label: SettingsNavigation.page_title(:leaves),
        icon: "calendar-days",
        path: SettingsNavigation.canonical_path(:leaves),
        roles: UserRole.roles()
      },
      %{
        id: :account,
        layer: :me,
        label: pgettext("sidebar", "My account"),
        icon: "konto",
        path: SettingsNavigation.canonical_path(:account),
        roles: UserRole.roles()
      }
    ]
  end
end
