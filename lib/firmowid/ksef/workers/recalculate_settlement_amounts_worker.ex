defmodule Firmowid.Ksef.Workers.RecalculateSettlementAmountsWorker do
  @moduledoc """
  One-off correction of KSeF cost invoices imported while their amount left out charges and
  deductions (Rozliczenie), such as a bottle deposit. It re-parses each stored invoice XML and
  stores the amount due where it differs.

  Enqueued by the `RecalculateKsefSettlementAmounts` migration, because the XML lives in S3,
  which a migration cannot read. Remove this worker once the job has run in production.
  """

  use Oban.Worker, queue: :cost_invoices, max_attempts: 3

  alias Firmowid.Ksef.Services.InvoiceParser
  alias Firmowid.Repo
  alias Firmowid.S3Client

  require Logger

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: Oban.Worker.result()
  def perform(%Oban.Job{}) do
    %{rows: rows} =
      Repo.query!(
        """
        SELECT ci.id, b.blob_path
        FROM cost_invoices ci
        JOIN blobs b ON b.id = ci.blob_id
        WHERE ci.ksef_number IS NOT NULL
        """,
        [],
        skip_organization_id: true
      )

    corrected = Enum.count(rows, &correct_amount/1)

    Logger.info("Recalculated KSeF cost invoice amounts: checked=#{length(rows)} corrected=#{corrected}")

    :ok
  end

  defp correct_amount([id, blob_path]) do
    {:ok, url} = S3Client.presigned_get_url(blob_path)
    {:ok, %{amount: amount}} = url |> Req.get!() |> Map.fetch!(:body) |> InvoiceParser.parse()
    amount_due = amount |> Money.to_decimal() |> Decimal.negate()

    %{num_rows: num_rows} =
      Repo.query!(
        """
        UPDATE cost_invoices
        SET amount = ((amount).currency_code, $2)::money_with_currency
        WHERE id = $1 AND (amount).amount <> $2
        """,
        [id, amount_due],
        skip_organization_id: true
      )

    num_rows == 1
  end
end
