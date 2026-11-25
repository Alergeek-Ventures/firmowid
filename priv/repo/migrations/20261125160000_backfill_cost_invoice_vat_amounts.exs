defmodule Firmowid.Repo.Migrations.BackfillCostInvoiceVatAmounts do
  @moduledoc """
  Used to enqueue the one-off job that filled the Polish VAT of KSeF cost invoices imported
  before the `vat_amount` column existed, from their XML in S3. The job ran in production on
  2026-11-25 and its worker is removed, so the migration now does nothing: enqueuing would leave
  a job no worker can run.
  """

  use Ecto.Migration

  def up, do: :ok

  def down, do: :ok
end
