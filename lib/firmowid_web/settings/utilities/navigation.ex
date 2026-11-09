defmodule FirmowidWeb.Settings.Utilities.Navigation do
  @moduledoc """
  Central navigation contract for settings routes.
  """

  use FirmowidWeb, :verified_routes
  use Gettext, backend: Firmowid.Gettext

  alias Firmowid.Core.UserRole

  @type role :: UserRole.t()
  @type tab_id :: :account | :profile | :organization | :subscription
  @type page_id :: tab_id() | :ksef | :bank_accounts | :roles | :documents | :delegations
  @type tab :: %{id: tab_id(), label: String.t(), path: String.t()}
  @type visibility_context :: %{
          required(:current_user) => %{
            required(:id) => term(),
            required(:member) => %{required(:role) => role()}
          },
          required(:current_org) => %{required(:owner_id) => term()}
        }

  @all_roles UserRole.roles()

  @tabs [
    %{
      id: :account,
      slug: "konto",
      label: pgettext_noop("Firmowid account", "settings tab"),
      roles: @all_roles,
      legacy_slugs: ["bezpieczenstwo"]
    },
    %{
      id: :profile,
      slug: "profil",
      label: pgettext_noop("Your profile", "settings tab"),
      roles: @all_roles,
      legacy_slugs: ["dokumenty"]
    },
    %{
      id: :organization,
      slug: "firma",
      label: pgettext_noop("Your company", "settings tab"),
      roles: [:admin],
      legacy_slugs: ["organizacja", "konta-bankowe", "ksef", "role"]
    },
    %{
      id: :subscription,
      slug: "abonament",
      label: pgettext_noop("Subscription", "settings tab"),
      roles: @all_roles,
      owner_only: true,
      legacy_slugs: []
    }
  ]

  @doc """
  Returns visible settings tabs for the current user.
  """
  @spec tabs_for(visibility_context()) :: [tab()]
  def tabs_for(%{current_user: _current_user, current_org: _current_org} = context) do
    @tabs
    |> Enum.filter(&visible_for_context?(&1, context))
    |> Enum.map(
      &%{
        id: &1.id,
        label: Gettext.pgettext(Firmowid.Gettext, "settings tab", &1.label),
        path: canonical_path(&1.id)
      }
    )
  end

  @doc """
  Returns the default settings path.
  """
  @spec default_path() :: String.t()
  def default_path, do: canonical_path(:account)

  @doc """
  Returns the canonical path for a settings tab.
  """
  @spec canonical_path(page_id()) :: String.t()
  def canonical_path(:account), do: ~p"/ustawienia/konto"
  def canonical_path(:profile), do: ~p"/ustawienia/profil"
  def canonical_path(:organization), do: ~p"/ustawienia/firma"
  def canonical_path(:subscription), do: ~p"/ustawienia/abonament"

  def canonical_path(:ksef), do: ~p"/ustawienia/ksef"
  def canonical_path(:bank_accounts), do: ~p"/ustawienia/konta-bankowe"
  # The new UI manages roles and invitations on the team page.
  def canonical_path(:roles), do: ~p"/zarzadzanie/pracownicy"
  def canonical_path(:documents), do: ~p"/ustawienia/dokumenty"
  def canonical_path(:delegations), do: ~p"/ustawienia/delegacje"

  @doc "Returns the title of a standalone settings page."
  @spec page_title(page_id()) :: String.t()
  def page_title(:account), do: pgettext("sidebar", "My account")
  def page_title(:profile), do: gettext("HR details")
  def page_title(:organization), do: gettext("Company details")
  def page_title(:subscription), do: pgettext("settings tab", "Subscription")
  def page_title(:ksef), do: "KSeF"
  def page_title(:bank_accounts), do: gettext("Bank accounts")
  def page_title(:documents), do: gettext("My documents")
  def page_title(:delegations), do: gettext("My business trips")

  @doc """
  Resolves a settings section slug or legacy alias.
  """
  @spec resolve_section(String.t(), boolean()) ::
          {:ok, %{id: page_id(), canonical?: boolean(), canonical_path: String.t()}} | :error
  def resolve_section(section, standalone? \\ false)

  def resolve_section(section, true) when section in ["ksef", "konta-bankowe", "role", "dokumenty", "delegacje"] do
    id =
      %{
        "ksef" => :ksef,
        "konta-bankowe" => :bank_accounts,
        "role" => :roles,
        "dokumenty" => :documents,
        "delegacje" => :delegations
      }[section]

    {:ok, %{id: id, canonical?: true, canonical_path: canonical_path(id)}}
  end

  def resolve_section(section, _standalone?) when is_binary(section) do
    case Enum.find(@tabs, &(section == &1.slug or section in &1.legacy_slugs)) do
      %{id: id, slug: slug} ->
        {:ok, %{id: id, canonical?: section == slug, canonical_path: canonical_path(id)}}

      nil ->
        :error
    end
  end

  @doc """
  Returns whether a settings tab is visible for the current user.
  """
  @spec visible?(page_id(), visibility_context()) :: boolean()
  def visible?(tab_id, %{current_user: _current_user, current_org: _current_org} = context) do
    tab_id
    |> tab_definition()
    |> visible_for_context?(context)
  end

  defp tab_definition(id) when id in [:ksef, :bank_accounts, :roles], do: tab_definition(:organization)

  defp tab_definition(id) when id in [:documents, :delegations], do: tab_definition(:profile)
  defp tab_definition(tab_id), do: Enum.find(@tabs, &(&1.id == tab_id))

  defp visible_for_context?(%{roles: roles} = tab, %{current_user: %{member: %{role: role}}} = context) do
    role in roles and owner_requirement_met?(tab, context)
  end

  defp owner_requirement_met?(%{owner_only: true}, %{current_user: current_user, current_org: current_org}) do
    current_org.owner_id == current_user.id
  end

  defp owner_requirement_met?(_tab, _context), do: true
end
