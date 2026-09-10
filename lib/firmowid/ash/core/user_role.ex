defmodule Firmowid.Ash.Core.UserRole do
  @moduledoc """
  Organization membership roles.

  Hierarchy (lowest to highest):

      :employee < :invoicing < :accountant < :admin

  Used by Ash attribute constraints, `AtLeastRole` policy checks, and UI labels.
  """

  @type t :: :employee | :invoicing | :accountant | :admin

  @roles [:employee, :invoicing, :accountant, :admin]

  @labels %{
    employee: "pracownik",
    invoicing: "fakturowanie",
    accountant: "księgowość",
    admin: "admin"
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
  Returns the short Polish display label for a role.
  """
  @spec label(t() | term()) :: String.t()
  def label(role) when is_map_key(@labels, role), do: Map.fetch!(@labels, role)
  def label(role), do: to_string(role)

  @doc """
  Returns the form/param string for a role atom.
  """
  @spec param(t()) :: String.t()
  def param(role) when role in @roles, do: Atom.to_string(role)
end
