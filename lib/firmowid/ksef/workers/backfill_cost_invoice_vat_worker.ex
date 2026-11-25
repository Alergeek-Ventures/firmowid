defmodule Firmowid.Ksef.Workers.BackfillCostInvoiceVatWorker do
  @moduledoc """
  One-off backfill of the Polish VAT on KSeF cost invoices imported before `vat_amount` existed.
  It re-parses each stored invoice XML and stores the VAT where the column is still NULL.

  Enqueued by the `BackfillCostInvoiceVatAmounts` migration, because the XML lives in S3, which a
  migration cannot read. Remove this worker once the job has run in production.
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
        WHERE ci.ksef_number IS NOT NULL AND ci.vat_amount IS NULL
        """,
        [],
        skip_organization_id: true
      )

    {filled, unreadable} = Enum.reduce(rows, {0, 0}, &fill_vat_amount/2)

    Logger.info(
      "Backfilled KSeF cost invoice VAT: checked=#{length(rows)} filled=#{filled} " <>
        "unreadable=#{unreadable}"
    )

    :ok
  end

  # An XML the parser cannot read keeps its NULL VAT, so a retry sees only the rows left unfilled.
  # A document S3 does not return fails the job, which then retries the rows still unfilled.
  defp fill_vat_amount([id, blob_path], {filled, unreadable}) do
    {:ok, url} = S3Client.presigned_get_url(blob_path)
    %{status: 200, body: xml} = Req.get!(url)

    case InvoiceParser.parse(xml) do
      {:ok, %{vat_amount: vat_amount}} ->
        %{num_rows: num_rows} =
          Repo.query!(
            """
            UPDATE cost_invoices
            SET vat_amount = $2
            WHERE id = $1 AND vat_amount IS NULL
            """,
            [id, vat_amount],
            skip_organization_id: true
          )

        {filled + num_rows, unreadable}

      {:error, _reason} ->
        {filled, unreadable + 1}
    end
  end
end
