defmodule Firmowid.Core.UserRole do
  @moduledoc """
  Organization membership roles.

  Hierarchy (lowest to highest):

      :employee < :invoicing < :accountant < :admin

  Used by Ash attribute constraints, `AtLeastRole` policy checks, and UI labels.
  """

  use Gettext, backend: Firmowid.Gettext

  @type t :: :employee | :invoicing | :accountant | :admin

  @roles [:employee, :invoicing, :accountant, :admin]

  @labels %{
    employee: pgettext_noop("employee", "member role"),
    invoicing: pgettext_noop("invoicing", "member role"),
    accountant: pgettext_noop("accounting", "member role"),
    admin: pgettext_noop("admin", "member role")
  }

  @doc """
  Returns all organization roles from lowest to highest privilege.
  """
  @spec roles() :: [t()]
  def roles, do: @roles

  @doc """
  Returns whether `role` is a known organization role.
  """
  @spec valid?(term()) :: boolean()
  def valid?(role), do: role in @roles

  @doc """
  Returns the short display label for a role.
  """
  @spec label(t() | term()) :: String.t()
  def label(role) when is_map_key(@labels, role),
    do: Gettext.pgettext(Firmowid.Gettext, "member role", Map.fetch!(@labels, role))

  def label(role), do: to_string(role)

  @doc """
  Returns the form/param string for a role atom.
  """
  @spec param(t()) :: String.t()
  def param(role) when role in @roles, do: Atom.to_string(role)
end
