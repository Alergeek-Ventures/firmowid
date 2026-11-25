defmodule Firmowid.Blobs.Changes.EnforceOcrLimit do
  @moduledoc """
  Refuses a document for OCR once the organization's plan has no documents left
  this month (`Firmowid.Billing.PlanCatalog`, `monthly_ocr_documents`).

  Runs before the file is stored, so a refused upload leaves nothing behind and
  nothing is queued. A file the organization already holds (the retry of a
  failed one) is let through to the checksum conflict, which the caller handles.
  Parallel uploads may overshoot the limit slightly: nothing locks the count.
  """
  use Ash.Resource.Change
  use Gettext, backend: Firmowid.Gettext

  alias Firmowid.Billing.PlanCatalog
  alias Firmowid.Blobs
  alias Firmowid.Blobs.Blob
  alias Firmowid.Blobs.UploadFingerprint
  alias Firmowid.Core

  require Ash.Query

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      if Ash.Changeset.get_argument(changeset, :processing_target) in [nil, :none],
        do: changeset,
        else: check(changeset, Ash.Context.to_opts(context))
    end)
  end

  defp check(changeset, opts) do
    plan = changeset.tenant |> Core.get_organization!(opts) |> Map.fetch!(:billing_plan)

    case PlanCatalog.plan!(plan).monthly_ocr_documents do
      :unlimited ->
        changeset

      limit ->
        if Blobs.count_ocr_documents(opts) >= limit and not stored?(changeset, opts),
          do:
            Ash.Changeset.add_error(changeset,
              field: :processing_target,
              message: gettext_noop("Your plan's monthly limit of documents for OCR is used up.")
            ),
          else: changeset
    end
  end

  defp stored?(changeset, opts) do
    checksum =
      UploadFingerprint.normalized_checksum(
        Ash.Changeset.get_argument(changeset, :upload_path),
        Ash.Changeset.get_argument(changeset, :content_type)
      )

    # Only whether the file exists is read, whoever may read it.
    Ash.exists?(
      Ash.Query.filter(Blob, blob_checksum == ^checksum),
      Keyword.put(opts, :authorize?, false)
    )
  end
end
