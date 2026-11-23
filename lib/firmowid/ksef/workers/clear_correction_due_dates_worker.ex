defmodule Firmowid.Ksef.Workers.ClearCorrectionDueDatesWorker do
  @moduledoc """
  One-off correction of KSeF cost invoice corrections imported while the parser gave a
  correction without a payment term (TerminPlatnosci) its issue date as one. Such a correction
  leaves the corrected invoice's term in force, so the job re-parses each stored correction XML
  and clears the due date the XML does not state.

  Enqueued by the `ClearKsefCorrectionDueDates` migration, because the XML lives in S3, which a
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
        WHERE ci.ksef_number IS NOT NULL
          AND ci.original_invoice_ksef_number IS NOT NULL
          AND ci.due_date IS NOT NULL
        """,
        [],
        skip_organization_id: true
      )

    cleared = Enum.count(rows, &clear_unstated_due_date/1)

    Logger.info("Cleared KSeF correction due dates: checked=#{length(rows)} cleared=#{cleared}")

    :ok
  end

  defp clear_unstated_due_date([id, blob_path]) do
    {:ok, url} = S3Client.presigned_get_url(blob_path)

    case url |> Req.get!() |> Map.fetch!(:body) |> InvoiceParser.parse() do
      {:ok, %{due_date: nil}} ->
        %{num_rows: 1} =
          Repo.query!("UPDATE cost_invoices SET due_date = NULL WHERE id = $1", [id], skip_organization_id: true)

        true

      {:ok, _stated} ->
        false
    end
  end
end
