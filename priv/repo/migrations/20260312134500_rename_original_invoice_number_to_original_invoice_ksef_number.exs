defmodule Firmowid.Repo.Migrations.RenameOriginalInvoiceNumberToOriginalInvoiceKsefNumber do
  use Ecto.Migration

  @moduledoc "Renames the corrected cost invoice KSeF reference column to the precise name."

  def up do
    rename table(:cost_invoices), :original_invoice_number, to: :original_invoice_ksef_number
  end

  def down do
    rename table(:cost_invoices), :original_invoice_ksef_number, to: :original_invoice_number
  end
end
