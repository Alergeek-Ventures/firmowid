defmodule Firmowid.Repo.Migrations.SeedOrganizationLimits do
  @moduledoc """
  Seeds organization_limits for existing organizations with default values.
  """
  use Ecto.Migration

  def up do
    execute("""
    INSERT INTO organization_limits (
      id,
      organization_id,
      cost_invoices_used,
      cost_invoices_limit,
      sales_invoices_used,
      sales_invoices_limit,
      bank_connections_used,
      bank_connections_limit,
      inserted_at,
      updated_at
    )
    SELECT
      gen_random_uuid(),
      o.id,
      0,
      100,
      0,
      100,
      0,
      5,
      NOW(),
      NOW()
    FROM organizations o
    WHERE NOT EXISTS (
      SELECT 1 FROM organization_limits ol WHERE ol.organization_id = o.id
    )
    """)
  end

  def down do
    execute("DELETE FROM organization_limits")
  end
end
