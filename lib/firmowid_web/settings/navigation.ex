defmodule FirmowidWeb.Settings.Navigation do
  @moduledoc """
  Central navigation contract for settings routes.
  """

  use FirmowidWeb, :verified_routes

  @type role :: :employee | :invoicing | :accountant | :admin
  @type tab_id :: :account | :profile | :organization | :invoices
  @type tab :: %{id: tab_id(), label: String.t(), path: String.t()}

  @all_roles [:employee, :invoicing, :accountant, :admin]

  @tabs [
    %{
      id: :account,
      slug: "konto",
      label: "Konto Firmowid",
      roles: @all_roles,
      legacy_slugs: ["bezpieczenstwo"]
    },
    %{id: :profile, slug: "profil", label: "Twój profil", roles: @all_roles, legacy_slugs: []},
    %{
      id: :organization,
      slug: "firma",
      label: "Twoja firma",
      roles: [:admin],
      legacy_slugs: ["organizacja", "konta-bankowe"]
    },
    %{id: :invoices, slug: "fakturowanie", label: "Faktury", roles: @all_roles, legacy_slugs: []}
  ]

  @doc """
  Returns visible settings tabs for the current user.
  """
  @spec tabs_for(%{role: role()}) :: [tab()]
  def tabs_for(%{role: role}) do
    @tabs
    |> Enum.filter(&visible_for_role?(&1, role))
    |> Enum.map(&%{id: &1.id, label: &1.label, path: canonical_path(&1.id)})
  end

  @doc """
  Returns the default settings path.
  """
  @spec default_path() :: String.t()
  def default_path, do: canonical_path(:account)

  @doc """
  Returns the canonical path for a settings tab.
  """
  @spec canonical_path(tab_id()) :: String.t()
  def canonical_path(:account), do: ~p"/ustawienia/konto"
  def canonical_path(:profile), do: ~p"/ustawienia/profil"
  def canonical_path(:organization), do: ~p"/ustawienia/firma"
  def canonical_path(:invoices), do: ~p"/ustawienia/fakturowanie"

  @doc """
  Resolves a settings section slug or legacy alias.
  """
  @spec resolve_section(String.t()) ::
          {:ok, %{id: tab_id(), canonical?: boolean(), canonical_path: String.t()}} | :error
  def resolve_section(section) when is_binary(section) do
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
  @spec visible?(tab_id(), %{role: role()}) :: boolean()
  def visible?(tab_id, %{role: role}) do
    tab_id
    |> tab_definition()
    |> visible_for_role?(role)
  end

  defp tab_definition(tab_id), do: Enum.find(@tabs, &(&1.id == tab_id))

  defp visible_for_role?(%{roles: roles}, role), do: role in roles
end
