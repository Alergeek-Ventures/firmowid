defmodule Firmowid.Ash.Ksef do
  @moduledoc """
  KSeF (Krajowy System e-Faktur) Ash domain.

  Handles Poland's national e-invoicing integration:
  - Authentication (token-based, per-organization)
  - Cost invoice fetching (encrypted export → XML parsing → CostInvoice creation)
  - Sales invoice submission (XML rendering → encryption → send → poll for confirmation)
  - Session management (access token caching via Cachex, refresh token rotation)
  - Submission status tracking (Oban job queries → SubmissionInfo struct)
  """

  use Ash.Domain

  import Ecto.Query, warn: false

  alias Firmowid.Accounts
  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Ksef.Credential
  alias Firmowid.Ash.Ksef.Services.ApiClient
  alias Firmowid.Ash.Ksef.SubmissionInfo
  alias Firmowid.Ash.Ksef.Workers.FetchWorker
  alias Firmowid.Ash.Ksef.Workers.SessionWorker
  alias Firmowid.Ash.Ksef.Workers.SubmissionWorker
  alias Firmowid.Repo

  resources do
    resource Credential
  end

  @ksef_broadcast_topic "ksef_status"

  # PubSub for KSeF status updates

  @doc """
  Subscribes to KSeF status updates for an organization.

  Messages received will be in the format:
  `{:ksef_invoice_status, %{invoice_id: id, status: :submitted | :failed}}`
  """
  @spec subscribe_ksef_status(String.t()) :: :ok | {:error, term()}
  def subscribe_ksef_status(organization_id) do
    Phoenix.PubSub.subscribe(Firmowid.PubSub, "#{@ksef_broadcast_topic}:#{organization_id}")
  end

  @doc """
  Broadcasts a KSeF status change for an invoice.

  Status can be `:submitted` (successfully received KSeF number) or `:failed` (submission failed).
  """
  @spec broadcast_ksef_status(Ash.UUID.t(), Ash.UUID.t(), :submitted | :failed) ::
          :ok | {:error, term()}
  def broadcast_ksef_status(organization_id, invoice_id, status) do
    Phoenix.PubSub.broadcast(
      Firmowid.PubSub,
      "#{@ksef_broadcast_topic}:#{organization_id}",
      {:ksef_invoice_status, %{invoice_id: invoice_id, status: status}}
    )
  end

  # Authentication

  @doc """
  Authenticates the current organization with KSeF using the provided token.

  The token format is: `<id>|nip-<nip>|<hash>`
  Example: `20251129-EC-2880DEC000-943359B3B3-DA|nip-1234563218|7489ef19...`

  Returns:
    - `{:ok, credential}` on success
    - `{:error, :invalid_token_format}` if token format is invalid
    - `{:error, :nip_mismatch}` if NIP in token doesn't match organization's NIP
    - `{:error, :already_connected}` if organization already has KSeF credentials
  """
  @spec authenticate_with_ksef_token(String.t()) ::
          {:ok, Credential.t()}
          | {:error, :invalid_token_format | :nip_mismatch | :already_connected}
  def authenticate_with_ksef_token(ksef_token) when is_binary(ksef_token) do
    org_id = Repo.get_org_id()
    {:ok, organization} = Accounts.get_organization(org_id)

    with {:ok, token_nip} <- extract_nip_from_token(ksef_token),
         :ok <- validate_nip_match(token_nip, organization.nip),
         :ok <- validate_no_existing_credential() do
      {:ok, credential} =
        Credential.create(%{
          organization_id: org_id,
          auth_type: :token,
          credentials: ksef_token
        })

      %{"organization_id" => org_id}
      |> SessionWorker.new()
      |> Firmowid.Oban.insert!()

      {:ok, credential}
    end
  end

  defp extract_nip_from_token(token) do
    case String.split(token, "|") do
      [_id, "nip-" <> nip, _hash] when byte_size(nip) > 0 ->
        {:ok, nip}

      _ ->
        {:error, :invalid_token_format}
    end
  end

  defp validate_nip_match(token_nip, org_nip) do
    # Normalize NIPs by removing any non-digit characters for comparison
    normalized_token_nip = String.replace(token_nip, ~r/\D/, "")
    normalized_org_nip = String.replace(org_nip || "", ~r/\D/, "")

    if normalized_token_nip == normalized_org_nip do
      :ok
    else
      {:error, :nip_mismatch}
    end
  end

  defp validate_no_existing_credential do
    case get_credential() do
      nil -> :ok
      _credential -> {:error, :already_connected}
    end
  end

  @doc """
  Returns the KSeF credential for the current organization, or `nil` if none exists.
  """
  @spec get_credential() :: Credential.t() | nil
  def get_credential do
    org_id = Repo.get_org_id()

    case Credential.get_by_organization(org_id) do
      {:ok, credential} -> credential
      {:error, %Ash.Error.Query.NotFound{}} -> nil
      _ -> nil
    end
  end

  @doc """
  Disconnects the current organization from KSeF.

  Invalidates the cached access token, cancels all pending KSeF jobs,
  and deletes the stored credential.
  """
  @spec unauthenticate() :: {:ok, term()} | {:error, term()}
  def unauthenticate do
    SessionWorker.invalidate_access_token()

    Repo.transact(fn ->
      credential = get_credential()

      Firmowid.Oban.cancel_all_jobs(
        from(j in Oban.Job,
          where:
            j.worker in [
              "Firmowid.Ash.Ksef.Workers.SessionWorker",
              "Firmowid.Ash.Ksef.Workers.FetchWorker"
            ],
          where: fragment("?->>'organization_id' = ?", j.args, ^Repo.get_org_id()),
          where: j.state in ["available", "scheduled", "executing"]
        )
      )

      Credential.destroy!(credential)
    end)
  end

  @doc """
  Enqueues an Oban job to fetch cost invoices from KSeF starting from `date_from`.
  """
  @spec fetch_cost_invoices(DateTime.t()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def fetch_cost_invoices(date_from) do
    %{
      "action" => "initiate_export",
      "organization_id" => Repo.get_org_id(),
      "date_from" => DateTime.to_iso8601(date_from)
    }
    |> FetchWorker.new()
    |> Firmowid.Oban.insert()
  end

  @doc """
  Fetches FA XML invoice by KSeF number.
  Rate limit 64 req/h
  """
  @spec get_invoice_xml_by_ksef_number(String.t()) :: {:ok, binary()} | {:error, term()}
  def get_invoice_xml_by_ksef_number(ksef_number) when is_binary(ksef_number) do
    with :ok <- validate_ksef_authenticated() do
      access_token = SessionWorker.get_access_token!()
      ApiClient.get_invoice_xml(access_token, ksef_number)
    end
  end

  @doc """
  Submits a sales invoice to KSeF.

  The invoice must be fully confirmed and not already locked.
  This function enqueues a submission job that will:
  1. Open an online session with KSeF
  2. Generate FA(3) XML from the invoice
  3. Encrypt and submit the invoice
  4. Close the session
  5. Poll for the KSeF number

  Returns `{:ok, job}` on success, or `{:error, reason}` if the submission cannot be started.

  Possible errors:
  - `:not_authenticated` - Organization is not connected to KSeF
  - `:invoice_not_found` - Invoice with given ID doesn't exist
  - `:invoice_is_draft` - Invoice is a draft (has no invoice number)
  - `:invoice_already_locked` - Invoice has already been submitted or manually locked
  - `{:invalid_for_ksef, errors}` - Invoice is missing required fields for KSeF submission
  """
  @spec submit_sales_invoice(Ash.UUID.t()) ::
          {:ok, Oban.Job.t()}
          | {:error,
             :not_authenticated
             | :invoice_not_found
             | :invoice_is_draft
             | :invoice_already_locked
             | {:invalid_for_ksef, list()}}
  def submit_sales_invoice(sales_invoice_id) do
    with :ok <- validate_ksef_authenticated(),
         {:ok, invoice} <- validate_invoice_for_submission(sales_invoice_id) do
      %{
        "action" => "submit",
        "organization_id" => Repo.get_org_id(),
        "sales_invoice_id" => invoice.id
      }
      |> SubmissionWorker.new()
      |> Firmowid.Oban.insert()
    end
  end

  defp validate_ksef_authenticated do
    case get_credential() do
      nil -> {:error, :not_authenticated}
      _credential -> :ok
    end
  end

  defp validate_invoice_for_submission(sales_invoice_id) do
    opts = [tenant: Repo.get_org_id(), authorize?: false, actor: %{}]

    case SalesInvoice.by_id(sales_invoice_id, opts) do
      {:ok, nil} -> {:error, :invoice_not_found}
      {:ok, invoice} -> validate_invoice_state(invoice)
      {:error, _} -> {:error, :invoice_not_found}
    end
  end

  defp validate_invoice_state(invoice) do
    cond do
      not is_nil(invoice.ksef_number) -> {:error, :invoice_already_locked}
      is_nil(invoice.invoice_number) -> {:error, :invoice_is_draft}
      true -> validate_ksef_required_fields(invoice)
    end
  end

  @ksef_required_fields [
    :seller_nip,
    :seller_display_name,
    :seller_address,
    :issue_date,
    :invoice_number
  ]

  defp validate_ksef_required_fields(invoice) do
    missing = Enum.filter(@ksef_required_fields, &is_nil(Map.get(invoice, &1)))

    if missing == [] do
      {:ok, invoice}
    else
      {:error, {:invalid_for_ksef, Enum.map(missing, &{&1, {"is required for KSeF submission", []}})}}
    end
  end

  @doc """
  Generates the KSeF verification URL for an invoice (sales or cost).

  For sales invoices, backfills the checksum from KSeF API if missing.
  Raises on cost invoices without a KSeF number.
  """
  @spec invoice_url!(map()) :: String.t()
  def invoice_url!(%{seller_nip: seller_nip, issue_date: issue_date, ksef_number: ksef_number} = invoice)
      when not is_nil(ksef_number) do
    checksum = invoice.ksef_invoice_checksum || backfill_ksef_checksum!(invoice)
    invoice_url(seller_nip, issue_date, checksum)
  end

  def invoice_url!(%CostInvoice{seller_nip: seller_nip, issue_date: issue_date} = invoice) do
    if is_nil(invoice.ksef_number) do
      raise ArgumentError, "Cannot generate KSeF URL for non-KSeF-imported cost invoice"
    else
      invoice =
        Ash.load!(invoice, [:blob],
          authorize?: false,
          actor: %{},
          tenant: invoice.organization_id
        )

      checksum =
        invoice.blob.blob_checksum
        |> Base.decode16!(case: :lower)
        |> Base.url_encode64(padding: false)

      invoice_url(seller_nip, issue_date, checksum)
    end
  end

  defp invoice_url(seller_nip, issue_date, checksum) do
    base_url = Application.get_env(:firmowid, :ksef)[:qr_code_base_url]
    issue_date = Calendar.strftime(issue_date, "%d-%m-%Y")
    path = "/invoice/#{seller_nip}/#{issue_date}/#{checksum}"

    base_url
    |> URI.new!()
    |> URI.append_path(path)
    |> to_string()
  end

  defp backfill_ksef_checksum!(%{ksef_number: ksef_number} = invoice) do
    invoice_xml =
      case get_invoice_xml_by_ksef_number(ksef_number) do
        {:ok, xml} ->
          xml

        {:error, reason} ->
          raise "Failed to fetch KSeF invoice XML for checksum backfill: #{inspect(reason)}"
      end

    checksum = compute_fa3_checksum(invoice_xml)

    SalesInvoice.update_ksef_fields!(
      invoice,
      %{ksef_invoice_checksum: checksum},
      authorize?: false,
      actor: %{},
      tenant: invoice.organization_id
    )

    checksum
  end

  @doc "Computes SHA-256 checksum of FA(3) XML content, URL-safe base64 encoded."
  @spec compute_fa3_checksum(binary()) :: String.t()
  def compute_fa3_checksum(xml_content) when is_binary(xml_content) do
    :sha256
    |> :crypto.hash(xml_content)
    |> Base.url_encode64(padding: false)
  end

  # Submission Info

  @doc """
  Returns comprehensive KSeF submission information for a sales invoice.

  This function encapsulates all logic for determining submission status,
  timestamps, and error details. Use this instead of checking individual
  fields or querying Oban directly.

  ## Statuses

  - `:not_submitted` - Invoice has never been submitted to KSeF
  - `:submitting` - Submission is in progress (job pending/executing)
  - `:submitted` - Successfully confirmed by KSeF (has ksef_number)
  - `:failed` - Submission was attempted but failed

  ## Examples

      iex> get_submission_info(%SalesInvoice{ksef_number: "1234567890"})
      %SubmissionInfo{status: :submitted, ksef_number: "1234567890", ...}

      iex> get_submission_info(%SalesInvoice{ksef_session_reference_number: nil, ksef_number: nil})
      %SubmissionInfo{status: :not_submitted}
  """
  # Bridge: accepts both Ecto SalesInvoice and Ash SalesInvoice structs.
  # Map patterns used instead of %SalesInvoice{} — dies by starvation in Slice 7.
  @spec get_submission_info(map()) :: SubmissionInfo.t()
  def get_submission_info(%{ksef_number: ksef_number} = invoice) when not is_nil(ksef_number) do
    # Successfully submitted - has KSeF number
    job = get_latest_submission_job(invoice.id)

    %SubmissionInfo{
      status: :submitted,
      ksef_number: ksef_number,
      session_reference: invoice.ksef_session_reference_number,
      submitted_at: get_job_timestamp(job, :inserted_at),
      confirmed_at: get_job_timestamp(job, :completed_at) || invoice.locked_at
    }
  end

  def get_submission_info(%{ksef_session_reference_number: ref} = invoice) when not is_nil(ref) do
    # Has session reference - check job status for submitting vs failed
    job = get_latest_submission_job(invoice.id)

    case job_status(job) do
      :failed ->
        %SubmissionInfo{
          status: :failed,
          session_reference: ref,
          submitted_at: get_job_timestamp(job, :inserted_at),
          failed_at: get_job_failed_at(job),
          error: format_job_error(job)
        }

      :pending ->
        %SubmissionInfo{
          status: :submitting,
          session_reference: ref,
          submitted_at: get_job_timestamp(job, :inserted_at)
        }

      :completed ->
        # Job completed but no ksef_number - unusual state, treat as failed
        %SubmissionInfo{
          status: :failed,
          session_reference: ref,
          submitted_at: get_job_timestamp(job, :inserted_at),
          failed_at: get_job_timestamp(job, :completed_at),
          error: "Wysyłka zakończona bez potwierdzenia z KSeF"
        }

      nil ->
        # No job found but has session reference - treat as failed
        %SubmissionInfo{
          status: :failed,
          session_reference: ref,
          error: "Brak informacji o wysyłce"
        }
    end
  end

  def get_submission_info(%{id: _id} = invoice) do
    # No session reference - check if there's a pending job
    job = get_latest_submission_job(invoice.id)

    case job_status(job) do
      :pending ->
        %SubmissionInfo{
          status: :submitting,
          submitted_at: get_job_timestamp(job, :inserted_at)
        }

      :failed ->
        %SubmissionInfo{
          status: :failed,
          submitted_at: get_job_timestamp(job, :inserted_at),
          failed_at: get_job_failed_at(job),
          error: format_job_error(job)
        }

      _ ->
        %SubmissionInfo{status: :not_submitted}
    end
  end

  defp get_latest_submission_job(sales_invoice_id) do
    Oban.Job
    |> where(
      [j],
      j.worker == "Firmowid.Ash.Ksef.Workers.SubmissionWorker" and
        fragment("?->>'sales_invoice_id' = ?", j.args, ^to_string(sales_invoice_id))
    )
    |> order_by([j], desc: j.inserted_at)
    |> limit(1)
    |> Repo.one(oban_jobs: true)
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

  defp get_job_failed_at(nil), do: nil

  defp get_job_failed_at(%Oban.Job{errors: errors}) when is_list(errors) and errors != [] do
    # Get the timestamp from the last error
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

  defp format_job_error(nil), do: nil
  defp format_job_error(%Oban.Job{errors: []}), do: nil
  defp format_job_error(%Oban.Job{errors: nil}), do: nil

  defp format_job_error(%Oban.Job{errors: errors}) when is_list(errors) do
    # Get the last error (most recent attempt)
    case List.last(errors) do
      %{"error" => error_string} -> parse_error_string(error_string)
      _ -> "Wystąpił nieoczekiwany błąd podczas wysyłania do KSeF"
    end
  end

  defp parse_error_string(error_string) when is_binary(error_string) do
    cond do
      String.contains?(error_string, "invoice_processing_failed") ->
        extract_ksef_validation_error(error_string)

      String.contains?(error_string, "invoice_not_found") ->
        "Faktura nie została znaleziona"

      String.contains?(error_string, "invoice_is_draft") ->
        "Faktura jest szkicem - najpierw ją zatwierdź"

      String.contains?(error_string, "invoice_already_locked") ->
        "Faktura została już wysłana do KSeF"

      String.contains?(error_string, "not_authenticated") ->
        "Brak połączenia z KSeF"

      String.contains?(error_string, "invoice_duplicate") ->
        "Faktura została już wcześniej wysłana do KSeF"

      true ->
        "Wystąpił nieoczekiwany błąd podczas wysyłania do KSeF"
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
          "Błąd walidacji KSeF: #{Enum.join(details, "; ")}"
        end

      nil ->
        extract_ksef_description(error_string)
    end
  end

  defp extract_ksef_description(error_string) do
    # Try to extract description field
    case Regex.run(~r/"description"\s*=>\s*"([^"]+)"/, error_string) do
      [_, description] -> "Błąd KSeF: #{description}"
      nil -> "Błąd walidacji dokumentu przez KSeF"
    end
  end
end
