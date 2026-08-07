defmodule Firmowid.Repo.Migrations.AddAuditLog do
  @moduledoc """
  Audit log support was removed before deployment.

  This migration is intentionally a no-op so existing migration history stays intact.
  If `audit_logs` already exists locally from an earlier run, drop it manually.
  """

  use Ecto.Migration

  def up, do: :ok

  def down, do: :ok
end
