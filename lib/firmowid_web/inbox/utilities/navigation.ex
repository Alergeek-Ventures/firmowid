defmodule FirmowidWeb.Inbox.Utilities.Navigation do
  @moduledoc """
  Flat list of places in the app for the sidebar, split into the company layer
  and the member's own layer, plus the inbox URLs.
  """

  use FirmowidWeb, :verified_routes
  use Gettext, backend: Firmowid.Gettext

  alias Firmowid.Core.UserRole
  alias FirmowidWeb.Settings.Utilities.Navigation, as: SettingsNavigation

  @type layer :: :main | :company | :me
  @type destination :: %{
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

  @doc "Where a member reviews the leave requests of an employee."
  @spec employee_leaves_path(String.t()) :: String.t()
  def employee_leaves_path(member_id), do: ~p"/zarzadzanie/pracownicy/#{member_id}/urlopy"

  @doc "Company details settings."
  @spec company_settings_path() :: String.t()
  def company_settings_path, do: SettingsNavigation.canonical_path(:organization)

  @doc "KSeF integration settings."
  @spec ksef_settings_path() :: String.t()
  def ksef_settings_path, do: SettingsNavigation.canonical_path(:ksef)

  @doc "Bank account settings."
  @spec bank_settings_path() :: String.t()
  def bank_settings_path, do: SettingsNavigation.canonical_path(:bank_accounts)

  @doc """
  The destinations a member with `role` may open. `analysis?` reflects the
  analysis dashboard flag; `owner?` controls subscription visibility.
  """
  @spec for_role(UserRole.t(), boolean(), boolean()) :: [destination()]
  def for_role(role, analysis?, owner? \\ false) do
    Enum.filter(all(), fn destination ->
      role in destination.roles and (destination.id != :analysis or analysis?) and
        (destination.id != :subscription or owner?)
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
        icon: "inbox",
        path: ~p"/skrzynka",
        roles: UserRole.roles()
      },
      %{
        id: :timetracker,
        layer: :main,
        label: pgettext("main navigation", "Time tracking"),
        icon: "timer",
        path: ~p"/czasosledz",
        roles: UserRole.roles()
      },
      %{
        id: :invoices,
        layer: :company,
        label: gettext("Invoices"),
        icon: "file-text",
        path: ~p"/fakturowanie?#{[filtr: "faktury", widok: "lista"]}",
        roles: @managers
      },
      %{
        id: :transactions,
        layer: :company,
        label: gettext("Transactions"),
        icon: "arrow-left-right",
        path: ~p"/fakturowanie?#{[filtr: "transakcje", widok: "lista"]}",
        roles: @managers
      },
      %{
        id: :team,
        layer: :company,
        label: pgettext("sidebar", "Team"),
        icon: "users",
        path: ~p"/zarzadzanie/pracownicy",
        roles: [:admin]
      },
      %{
        id: :counterparties,
        layer: :company,
        label: pgettext("management navigation", "Counterparties"),
        icon: "building-2",
        path: ~p"/zarzadzanie/kontrahenci",
        roles: [:admin]
      },
      %{
        id: :projects,
        layer: :company,
        label: pgettext("management navigation", "Projects"),
        icon: "folder-kanban",
        path: ~p"/zarzadzanie/projekty",
        roles: [:admin]
      },
      %{
        id: :analysis,
        layer: :company,
        label: pgettext("main navigation", "Analysis"),
        icon: "chart-column",
        path: ~p"/analiza",
        roles: [:admin]
      },
      %{
        id: :company_settings,
        layer: :company,
        label: SettingsNavigation.page_title(:organization),
        icon: "briefcase",
        path: company_settings_path(),
        roles: [:admin]
      },
      %{
        id: :ksef,
        layer: :company,
        label: SettingsNavigation.page_title(:ksef),
        icon: "unplug",
        path: ksef_settings_path(),
        roles: [:admin]
      },
      %{
        id: :bank_accounts,
        layer: :company,
        label: SettingsNavigation.page_title(:bank_accounts),
        icon: "landmark",
        path: bank_settings_path(),
        roles: [:admin]
      },
      %{
        id: :roles,
        layer: :company,
        label: pgettext("sidebar", "Roles and invitations"),
        icon: "user-plus",
        path: SettingsNavigation.canonical_path(:roles),
        roles: [:admin]
      },
      %{
        id: :subscription,
        layer: :company,
        label: SettingsNavigation.page_title(:subscription),
        icon: "credit-card",
        path: SettingsNavigation.canonical_path(:subscription),
        roles: UserRole.roles()
      },
      %{
        id: :hours_record,
        layer: :me,
        label: pgettext("sidebar", "My hours record"),
        icon: "clipboard-list",
        path: ~p"/czasosledz/ewidencja",
        roles: UserRole.roles()
      },
      %{
        id: :profile,
        layer: :me,
        label: SettingsNavigation.page_title(:profile),
        icon: "id-card",
        path: SettingsNavigation.canonical_path(:profile),
        roles: UserRole.roles()
      },
      %{
        id: :documents,
        layer: :me,
        label: SettingsNavigation.page_title(:documents),
        icon: "files",
        path: SettingsNavigation.canonical_path(:documents),
        roles: UserRole.roles()
      },
      %{
        id: :account,
        layer: :me,
        label: pgettext("sidebar", "My account"),
        icon: "settings",
        path: SettingsNavigation.canonical_path(:account),
        roles: UserRole.roles()
      }
    ]
  end
end
