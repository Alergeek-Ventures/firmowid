defmodule Firmowid.Blobs.Preparations.OcrDocumentsThisMonth do
  @moduledoc """
  Narrows a blob query to the documents sent to OCR in the current billing month:
  a processing target other than `:none`, created this calendar month in
  Europe/Warsaw. A failed blob is deleted after an hour and does not count; it
  counts again once it is run again.
  """
  use Ash.Resource.Preparation

  alias Firmowid.Billing.Month

  require Ash.Query

  @impl true
  def prepare(query, _opts, _context) do
    {from, to} = Month.utc_bounds(Month.current())

    Ash.Query.filter(
      query,
      processing_target != :none and processing_state != :failed and inserted_at >= ^from and
        inserted_at < ^to
    )
  end
end
