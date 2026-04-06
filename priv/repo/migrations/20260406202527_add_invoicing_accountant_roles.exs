defmodule Firmowid.Repo.Migrations.AddInvoicingAccountantRoles do
  @moduledoc """
  Extends User.role to include :invoicing and :accountant.

  The role attribute is stored as :text with no DB-level enum constraint,
  so no schema change is required — only the Ash snapshot is updated to
  reflect the new allowed values in the one_of constraint.
  """

  use Ecto.Migration

  def up, do: :ok
  def down, do: :ok
end
