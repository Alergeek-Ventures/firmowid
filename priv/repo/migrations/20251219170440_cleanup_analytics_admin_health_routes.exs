defmodule Firmowid.Repo.Migrations.CleanupAnalyticsAdminHealthRoutes do
  use Ecto.Migration

  def up do
    execute """
    DELETE FROM requests
    WHERE path LIKE '/admin%' OR path = '/health'
    """
  end

  def down do
    # Data deletion is not reversible
    :ok
  end
end
