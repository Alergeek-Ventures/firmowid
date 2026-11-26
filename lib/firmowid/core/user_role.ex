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
  Returns what a role may do, in a sentence for choosing a role.
  """
  @spec description(t()) :: String.t()
  def description(:admin) do
    gettext(
      "Full access to the \"Management\" tab, including managing employees, counterparties and projects. This role also gives full access to invoices and to uploading invoices from outside KSeF."
    )
  end

  def description(:employee) do
    gettext(
      "Basic access to the organization, including the Time Tracker (working time tracking). The ability to submit leave requests and upload documents."
    )
  end

  def description(:invoicing) do
    gettext("Invoicing access in view-only mode, without the ability to add or edit.")
  end

  def description(:accountant) do
    gettext("Full invoicing access (viewing, adding and editing), except for adding invoices from outside KSeF.")
  end

  @doc """
  Returns the form/param string for a role atom.
  """
  @spec param(t()) :: String.t()
  def param(role) when role in @roles, do: Atom.to_string(role)

  @doc """
  Parses a role from its form/param string.
  """
  @spec from_param(term()) :: {:ok, t()} | {:error, :unknown_role}
  def from_param(param) do
    case Enum.find(@roles, &(param(&1) == param)) do
      nil -> {:error, :unknown_role}
      role -> {:ok, role}
    end
  end
end
