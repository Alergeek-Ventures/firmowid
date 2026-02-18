defmodule Firmowid.Repo.Migrations.AddCorrectionReasonToSalesInvoices do
  use Ecto.Migration

  def change do
    alter table(:sales_invoices) do
      add :correction_reason, :string, size: 256
    end
  end
end
