defmodule FirmowidWeb.Settings.Utilities.Navigation do
  @moduledoc """
  Central navigation contract for settings routes.
  """

  use FirmowidWeb, :verified_routes
  use Gettext, backend: Firmowid.Gettext

  alias Firmowid.Core.UserRole

  @type page_id ::
          :account
          | :profile
          | :organization
          | :subscription
          | :ksef
          | :bank_accounts
          | :integrations
          | :roles
          | :documents
          | :delegations
          | :leaves
  @type integration :: :mcp | :api
  @type visibility_context :: %{
          required(:current_user) => %{
            required(:id) => term(),
            required(:member) => %{required(:role) => UserRole.t()}
          },
          required(:current_org) => %{required(:owner_id) => term()}
        }

  @slugs %{
    "konto" => :account,
    "profil" => :profile,
    "firma" => :organization,
    "abonament" => :subscription,
    "ksef" => :ksef,
    "konta-bankowe" => :bank_accounts,
    "integracje" => :integrations,
    "role" => :roles,
    "dokumenty" => :documents,
    "delegacje" => :delegations,
    "nieobecnosci" => :leaves
  }

  # Former addresses of settings pages, so that old links still lead to them.
  @legacy_slugs %{
    "bezpieczenstwo" => :account,
    "organizacja" => :organization,
    "klucze-api" => :integrations
  }

  @admin_pages [:organization, :ksef, :bank_accounts, :roles]

  @doc """
  Returns the default settings path.
  """
  @spec default_path() :: String.t()
  def default_path, do: canonical_path(:account)

  @doc """
  Returns the canonical path for a settings page.
  """
  @spec canonical_path(page_id()) :: String.t()
  def canonical_path(:account), do: ~p"/ustawienia/konto"
  def canonical_path(:profile), do: ~p"/ustawienia/profil"
  def canonical_path(:organization), do: ~p"/ustawienia/firma"
  def canonical_path(:subscription), do: ~p"/ustawienia/abonament"

  def canonical_path(:ksef), do: ~p"/ustawienia/ksef"
  def canonical_path(:bank_accounts), do: ~p"/ustawienia/konta-bankowe"
  def canonical_path(:integrations), do: ~p"/ustawienia/integracje"
  # Roles and invitations are managed on the team page.
  def canonical_path(:roles), do: ~p"/zarzadzanie/pracownicy"
  def canonical_path(:documents), do: ~p"/ustawienia/dokumenty"
  def canonical_path(:delegations), do: ~p"/ustawienia/delegacje"
  def canonical_path(:leaves), do: ~p"/ustawienia/nieobecnosci"

  @doc "Returns the title of a settings page."
  @spec page_title(page_id()) :: String.t()
  def page_title(:account), do: pgettext("sidebar", "Account")
  def page_title(:profile), do: gettext("HR details")
  def page_title(:organization), do: gettext("Company details")
  def page_title(:subscription), do: pgettext("settings tab", "Subscription")
  def page_title(:ksef), do: "KSeF"
  def page_title(:bank_accounts), do: gettext("Bank accounts")
  def page_title(:integrations), do: gettext("Integrations")
  def page_title(:documents), do: gettext("Documents")
  def page_title(:delegations), do: gettext("Business trips")
  def page_title(:leaves), do: gettext("Absences")

  @integration_slugs %{"asystenci-ai" => :mcp, "api" => :api}

  @doc "Resolves the slug of an integration's subpage of the integrations page."
  @spec resolve_integration(String.t()) :: {:ok, integration()} | :error
  def resolve_integration(slug), do: Map.fetch(@integration_slugs, slug)

  @doc "Returns the path of an integration's subpage."
  @spec integration_path(integration()) :: String.t()
  def integration_path(:mcp), do: ~p"/ustawienia/integracje/asystenci-ai"
  def integration_path(:api), do: ~p"/ustawienia/integracje/api"

  @doc "Returns the title of an integration's subpage."
  @spec integration_title(integration()) :: String.t()
  def integration_title(:mcp), do: gettext("AI assistants (MCP)")
  def integration_title(:api), do: gettext("REST API")

  @doc "Returns the integrations shown on the integrations page; every member may set them up."
  @spec integrations() :: [integration()]
  def integrations, do: [:mcp, :api]

  @doc """
  Resolves a settings section slug or legacy alias.
  """
  @spec resolve_section(String.t()) ::
          {:ok, %{id: page_id(), canonical?: boolean(), canonical_path: String.t()}} | :error
  def resolve_section(section) when is_binary(section) do
    case {@slugs[section], @legacy_slugs[section]} do
      {nil, nil} -> :error
      {nil, id} -> {:ok, %{id: id, canonical?: false, canonical_path: canonical_path(id)}}
      {id, nil} -> {:ok, %{id: id, canonical?: true, canonical_path: canonical_path(id)}}
    end
  end

  @doc """
  Returns whether a settings page is visible for the current user.
  """
  @spec visible?(page_id(), visibility_context()) :: boolean()
  def visible?(page_id, %{current_user: current_user}) when page_id in @admin_pages,
    do: current_user.member.role == :admin

  def visible?(:subscription, %{current_user: current_user, current_org: current_org}),
    do: current_org.owner_id == current_user.id

  def visible?(_page_id, %{current_user: _current_user, current_org: _current_org}), do: true
end
