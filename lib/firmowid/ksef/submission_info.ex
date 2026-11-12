defmodule Firmowid.Ksef.SubmissionInfo do
  @moduledoc """
  Struct representing the KSeF submission status for a sales invoice.

  Encapsulates all information about an invoice's KSeF submission lifecycle,
  including timestamps, identifiers, and error details. `for_invoice/1` and
  `for_invoices/1` derive it from the invoice and its latest `SubmissionWorker` job.

  ## Statuses

  - `:not_submitted` - Invoice has never been submitted to KSeF
  - `:submitting` - Submission is in progress (job pending/executing)
  - `:submitted` - Successfully confirmed by KSeF (has ksef_number)
  - `:failed` - Submission was attempted but failed

  ## Examples

      # Not submitted
      %SubmissionInfo{status: :not_submitted}

      # Successfully submitted
      %SubmissionInfo{
        status: :submitted,
        ksef_number: "1234567890-20260128-ABC123",
        session_reference: "20260128-SO-...",
        submitted_at: ~U[2026-01-28 21:54:04Z],
        confirmed_at: ~U[2026-01-28 21:54:10Z]
      }

      # Failed submission
      %SubmissionInfo{
        status: :failed,
        session_reference: "20260128-SO-...",
        submitted_at: ~U[2026-01-28 21:54:04Z],
        failed_at: ~U[2026-01-28 21:54:05Z],
        error: "Błąd walidacji KSeF: nieprawidłowy kod kraju"
      }
  """

  use Gettext, backend: Firmowid.Gettext

  import Ecto.Query

  alias Firmowid.Repo

  @type status :: :not_submitted | :submitting | :submitted | :failed

  @type t :: %__MODULE__{
          status: status(),
          submitted_at: DateTime.t() | nil,
          confirmed_at: DateTime.t() | nil,
          failed_at: DateTime.t() | nil,
          ksef_number: String.t() | nil,
          session_reference: String.t() | nil,
          error: String.t() | nil
        }

  defstruct [
    :status,
    :submitted_at,
    :confirmed_at,
    :failed_at,
    :ksef_number,
    :session_reference,
    :error
  ]

  @doc "Returns `true` if the invoice was successfully submitted to KSeF."
  @spec submitted?(t()) :: boolean()
  def submitted?(%__MODULE__{status: :submitted}), do: true
  def submitted?(%__MODULE__{}), do: false

  @doc "Returns `true` if the submission is currently in progress."
  @spec submitting?(t()) :: boolean()
  def submitting?(%__MODULE__{status: :submitting}), do: true
  def submitting?(%__MODULE__{}), do: false

  @doc "Returns whether normal invoice editing must be blocked."
  @spec editing_blocked?(map(), t()) :: boolean()
  def editing_blocked?(%{ksef_number: nil, locked_at: locked_at}, _submission_info) when not is_nil(locked_at), do: true

  def editing_blocked?(_invoice, submission_info), do: submitting?(submission_info)

  @doc """
  Returns whether a numbered invoice was issued outside KSeF, before KSeF was mandatory.
  Such invoices are kept for reference only and are neither edited nor corrected.
  """
  @spec outside_ksef?(map(), t()) :: boolean()
  def outside_ksef?(%{invoice_number: number, ksef_number: nil} = invoice, submission_info) when not is_nil(number),
    do: not editing_blocked?(invoice, submission_info)

  def outside_ksef?(_invoice, _submission_info), do: false

  @doc "Explains why an invoice issued outside KSeF cannot be edited."
  @spec outside_ksef_message() :: String.t()
  def outside_ksef_message, do: gettext("The invoice was issued outside KSeF — it cannot be edited or corrected.")

  @doc "Explains why the edit control is unavailable, for an invoice that is locked or outside KSeF."
  @spec edit_unavailable_reason(map(), t()) :: String.t()
  def edit_unavailable_reason(invoice, submission_info) do
    if outside_ksef?(invoice, submission_info),
      do: outside_ksef_message(),
      else: gettext("The invoice is locked. Editing will be available once the submission to KSeF is finished.")
  end

  @doc "Returns `true` if the submission failed."
  @spec failed?(t()) :: boolean()
  def failed?(%__MODULE__{status: :failed}), do: true
  def failed?(%__MODULE__{}), do: false

  @doc "Returns `true` if submission has been attempted (submitted, submitting, or failed)."
  @spec attempted?(t()) :: boolean()
  def attempted?(%__MODULE__{status: :not_submitted}), do: false
  def attempted?(%__MODULE__{}), do: true

  @doc """
  Returns the submission information of a sales invoice. Takes any map with the
  invoice's `id`, `ksef_number`, `ksef_session_reference_number` and `locked_at`.
  """
  @spec for_invoice(map()) :: t()
  def for_invoice(invoice) do
    [submission_info] = for_invoices([invoice])
    submission_info
  end

  @doc """
  Returns submission information in invoice order, fetching the latest submission
  job of every invoice in one query.
  """
  @spec for_invoices([map()]) :: [t()]
  def for_invoices([]), do: []

  def for_invoices(invoices) do
    jobs = get_latest_submission_jobs(Enum.map(invoices, & &1.id))

    Enum.map(invoices, fn invoice ->
      submission_info(invoice, Map.get(jobs, to_string(invoice.id)))
    end)
  end

  defp submission_info(%{ksef_number: ksef_number} = invoice, job) when not is_nil(ksef_number) do
    # Successfully submitted - has KSeF number
    %__MODULE__{
      status: :submitted,
      ksef_number: ksef_number,
      session_reference: invoice.ksef_session_reference_number,
      submitted_at: get_job_timestamp(job, :inserted_at),
      confirmed_at: get_job_timestamp(job, :completed_at) || invoice.locked_at
    }
  end

  defp submission_info(%{ksef_session_reference_number: ref}, job) when not is_nil(ref) do
    # Has session reference - check job status for submitting vs failed
    case job_status(job) do
      :failed ->
        %__MODULE__{
          status: :failed,
          session_reference: ref,
          submitted_at: get_job_timestamp(job, :inserted_at),
          failed_at: get_job_failed_at(job),
          error: format_job_error(job)
        }

      :pending ->
        %__MODULE__{
          status: :submitting,
          session_reference: ref,
          submitted_at: get_job_timestamp(job, :inserted_at)
        }

      :completed ->
        # Job completed but no ksef_number - unusual state, treat as failed
        %__MODULE__{
          status: :failed,
          session_reference: ref,
          submitted_at: get_job_timestamp(job, :inserted_at),
          failed_at: get_job_timestamp(job, :completed_at),
          error: gettext("Submission finished without confirmation from KSeF")
        }

      nil ->
        # No job found but has session reference - treat as failed
        %__MODULE__{
          status: :failed,
          session_reference: ref,
          error: gettext("No submission information")
        }
    end
  end

  defp submission_info(%{id: _id}, job) do
    # No session reference - check if there's a pending job
    case job_status(job) do
      :pending ->
        %__MODULE__{
          status: :submitting,
          submitted_at: get_job_timestamp(job, :inserted_at)
        }

      :failed ->
        %__MODULE__{
          status: :failed,
          submitted_at: get_job_timestamp(job, :inserted_at),
          failed_at: get_job_failed_at(job),
          error: format_job_error(job)
        }

      _ ->
        %__MODULE__{status: :not_submitted}
    end
  end

  # Oban.Job is not an Ash resource — raw Ecto query is required here.
  # TODO: Evaluate wrapping Oban job queries behind a dedicated module.
  defp get_latest_submission_jobs(sales_invoice_ids) do
    sales_invoice_ids = Enum.map(sales_invoice_ids, &to_string/1)

    Oban.Job
    |> where(
      [j],
      j.worker == "Firmowid.Ksef.Workers.SubmissionWorker" and
        fragment("?->>'sales_invoice_id'", j.args) in ^sales_invoice_ids
    )
    |> distinct([j], fragment("?->>'sales_invoice_id'", j.args))
    |> order_by([j], desc: j.inserted_at)
    |> Repo.all(oban_jobs: true)
    |> Map.new(fn job -> {job.args["sales_invoice_id"], job} end)
  end

  defp job_status(nil), do: nil

  defp job_status(%Oban.Job{state: state}) when state in ["discarded", "cancelled"], do: :failed

  defp job_status(%Oban.Job{state: state}) when state in ["available", "scheduled", "executing", "retryable"],
    do: :pending

  defp job_status(%Oban.Job{state: "completed"}), do: :completed
  defp job_status(%Oban.Job{}), do: nil

  defp get_job_timestamp(nil, _field), do: nil

  defp get_job_timestamp(%Oban.Job{} = job, field) do
    case Map.get(job, field) do
      %NaiveDateTime{} = dt -> DateTime.from_naive!(dt, "Etc/UTC")
      %DateTime{} = dt -> dt
      nil -> nil
    end
  end

  defp get_job_failed_at(%Oban.Job{errors: errors}) when is_list(errors) and errors != [] do
    case List.last(errors) do
      %{"at" => at_string} ->
        case DateTime.from_iso8601(at_string) do
          {:ok, dt, _offset} -> dt
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp get_job_failed_at(%Oban.Job{}), do: nil

  defp format_job_error(%Oban.Job{errors: []}), do: nil
  defp format_job_error(%Oban.Job{errors: nil}), do: nil

  defp format_job_error(%Oban.Job{errors: errors}) when is_list(errors) do
    case List.last(errors) do
      %{"error" => error_string} -> parse_error_string(error_string)
      _ -> gettext("An unexpected error occurred while sending to KSeF")
    end
  end

  defp parse_error_string(error_string) when is_binary(error_string) do
    cond do
      String.contains?(error_string, "invoice_processing_failed") ->
        extract_ksef_validation_error(error_string)

      String.contains?(error_string, "invoice_not_found") ->
        gettext("The invoice was not found")

      String.contains?(error_string, "invoice_is_draft") ->
        gettext("The invoice is a draft - approve it first")

      String.contains?(error_string, "invoice_already_locked") ->
        gettext("The invoice has already been sent to KSeF")

      String.contains?(error_string, "not_authenticated") ->
        gettext("No connection to KSeF")

      String.contains?(error_string, "invoice_duplicate") ->
        gettext("KSeF rejected the submission as a duplicate. Change the invoice data and send it again.")

      true ->
        gettext("An unexpected error occurred while sending to KSeF")
    end
  end

  defp extract_ksef_validation_error(error_string) do
    # Try to extract details from error like:
    # {:invoice_processing_failed, 450, %{"details" => ["error message"]}}
    case Regex.run(~r/"details"\s*=>\s*\[(.*?)\]/, error_string) do
      [_, details_content] ->
        # Extract quoted strings from the details array
        details =
          ~r/"([^"]+)"/
          |> Regex.scan(details_content)
          |> Enum.map(fn [_, detail] -> detail end)
          |> Enum.reject(&(&1 == "details"))

        if details == [] do
          extract_ksef_description(error_string)
        else
          gettext("KSeF validation error: %{details}", details: Enum.join(details, "; "))
        end

      nil ->
        extract_ksef_description(error_string)
    end
  end

  defp extract_ksef_description(error_string) do
    # Try to extract description field
    case Regex.run(~r/"description"\s*=>\s*"([^"]+)"/, error_string) do
      [_, description] -> gettext("KSeF error: %{description}", description: description)
      nil -> gettext("KSeF document validation error")
    end
  end
end
