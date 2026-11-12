defmodule Firmowid.Ksef do
  @moduledoc """
  KSeF (Krajowy System e-Faktur) Ash domain.

  Handles Poland's national e-invoicing integration:
  - Authentication (token-based, per-organization)
  - Invoice fetching (encrypted export → XML parsing → CostInvoice or SalesInvoice creation)
  - Sales invoice submission (XML rendering → encryption → send → poll for confirmation)
  - Session management (access token caching via Cachex, refresh token rotation)
  """

  use Ash.Domain, extensions: [AshAi]
  use Gettext, backend: Firmowid.Gettext

  import Ecto.Query, warn: false

  alias Firmowid.Core
  alias Firmowid.Invoicing
  alias Firmowid.Invoicing.CostInvoice
  alias Firmowid.Invoicing.SalesInvoice
  alias Firmowid.Ksef.Credential
  alias Firmowid.Ksef.CredentialMetadata
  alias Firmowid.Ksef.Services.ApiClient
  alias Firmowid.Ksef.Workers.FetchWorker
  alias Firmowid.Ksef.Workers.SessionWorker
  alias Firmowid.Ksef.Workers.SubmissionWorker
  alias Firmowid.Repo
  alias Firmowid.Scope
  alias Firmowid.SystemActor

  tools do
    tool :get_ksef_connection_status, Credential, :connection_status do
      annotations title: "Get KSeF connection status",
                  read_only_hint: true,
                  destructive_hint: false,
                  open_world_hint: false

      description "Check KSeF connection status before invoice work. If disconnected or expired, suggest show_ksef_connection when can_connect is true; otherwise ask an organization admin to connect. Stored invoices remain readable while disconnected. A connected status does not guarantee current invoice data: data_freshness is unknown. Never request tokens, certificates, private keys or passwords in chat."
    end

    tool :show_ksef_connection, Credential, :connection_status do
      annotations title: "Show KSeF connection",
                  read_only_hint: true,
                  destructive_hint: false,
                  open_world_hint: false

      description "Open the interactive KSeF connection setup inside the chat using a trusted profile or certificate; token registration is unavailable. After successfully opening the widget, stop: do not add a status table, summary, explanation or follow-up in chat. Let the user complete setup directly in the widget. This tool only reads status and makes no connection attempt, so an initial disconnected status is expected, not a failure. Only admins can connect or manage credentials. If can_connect is false, ask an organization admin to connect instead of opening the widget. Stored invoices remain readable while disconnected, and connected does not guarantee current data. Never request tokens, certificates, private keys or passwords in chat."
    end
  end

  resources do
    resource Credential do
      define :connection_status
      define :get_credential, action: :get, get?: true, not_found_error?: false
    end
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

  @doc "Stops KSeF status updates for an organization."
  @spec unsubscribe_ksef_status(String.t()) :: :ok
  def unsubscribe_ksef_status(organization_id) do
    Phoenix.PubSub.unsubscribe(Firmowid.PubSub, "#{@ksef_broadcast_topic}:#{organization_id}")
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

  @doc "Creates an unsigned AuthTokenRequest for the current organization."
  @spec prepare_external_auth_token_request(Scope.t()) ::
          {:ok, %{xml: String.t(), challenge: String.t()}}
          | {:error, :already_connected | term()}
  def prepare_external_auth_token_request(scope) do
    organization = Core.get_organization!(scope.tenant, scope: scope)

    with {:ok, %{challenge: challenge}} <- ApiClient.get_auth_challenge() do
      {:ok,
       %{
         xml: ApiClient.prepare_auth_token_request(organization.nip, challenge),
         challenge: challenge
       }}
    end
  end

  @doc """
  Returns whether the scope's organization has an active KSeF connection,
  using the metadata-only action available to invoice readers.
  """
  @spec connected?(Scope.t()) :: boolean()
  def connected?(scope), do: connection_status!(scope: scope).status == :connected

  @doc """
  Disconnects the given organization from KSeF.

  Invalidates the cached access token, cancels all pending KSeF jobs,
  and deletes the stored credential.
  """
  @spec unauthenticate(Scope.t()) :: {:ok, term()} | {:error, :not_connected | term()}
  def unauthenticate(scope) do
    org_id = scope.tenant

    case get_credential!(scope: scope) do
      nil ->
        {:error, :not_connected}

      credential ->
        access_token = SessionWorker.get_access_token!(org_id)

        with :ok <- maybe_revoke_generated_certificate(credential, access_token),
             :ok <- ApiClient.revoke_refresh_token(access_token),
             {:ok, _} <- SessionWorker.invalidate_access_token(org_id) do
          Repo.transact(fn ->
            # Oban.Job is not an Ash resource — raw Ecto query is required here.
            # TODO: Evaluate wrapping Oban job queries behind a dedicated module.
            Firmowid.Oban.cancel_all_jobs(
              from(j in Oban.Job,
                where:
                  j.worker in [
                    "Firmowid.Ksef.Workers.SessionWorker",
                    "Firmowid.Ksef.Workers.CertificateEnrollmentWorker",
                    "Firmowid.Ksef.Workers.FetchWorker",
                    "Firmowid.Ksef.Workers.SubmissionWorker"
                  ],
                where: fragment("?->>'organization_id' = ?", j.args, ^org_id),
                where: j.state in ["available", "scheduled", "executing", "retryable"]
              )
            )

            Credential.destroy!(credential, scope: scope)
            {:ok, :disconnected}
          end)
        end
    end
  end

  defp maybe_revoke_generated_certificate(%Credential{auth_type: :generated_certificate} = credential, access_token) do
    serial_number = CredentialMetadata.certificate_serial_number(credential)

    ApiClient.revoke_certificate(access_token, serial_number, :unspecified)
  end

  defp maybe_revoke_generated_certificate(%Credential{}, _access_token), do: :ok

  @doc """
  Enqueues Oban jobs fetching the organization's cost and sales invoices stored in KSeF
  since `date_from`.
  """
  @spec fetch_invoices(DateTime.t(), Scope.t()) :: :ok | {:error, term()}
  def fetch_invoices(date_from, scope), do: enqueue_fetches(fn _resource -> date_from end, scope)

  @doc """
  Enqueues fetches of cost and sales invoices stored in KSeF since the latest imported
  one of each kind, or from the last 60 days when none was imported yet.
  """
  @spec fetch_new_invoices(Scope.t()) :: :ok | {:error, term()}
  def fetch_new_invoices(scope) do
    enqueue_fetches(
      fn resource ->
        case Invoicing.last_ksef_permanent_storage_date(resource, scope.tenant) do
          nil -> DateTime.shift(DateTime.utc_now(), day: -60)
          date -> DateTime.from_naive!(date, "Etc/UTC")
        end
      end,
      scope
    )
  end

  defp enqueue_fetches(date_from, scope) do
    Enum.reduce_while([CostInvoice, SalesInvoice], :ok, fn resource, :ok ->
      case fetch(resource, date_from.(resource), scope) do
        {:ok, _job} -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  # One export at a time per organization and invoice kind: a new one is not started while
  # any job of a running one (its export, polls or continuations) is queued or running, so
  # pages are imported in order and the next fetch starts after everything saved.
  defp fetch(resource, date_from, scope) do
    %{
      "action" => "initiate_export",
      "organization_id" => scope.tenant,
      "subject_type" => subject_type(resource),
      "date_from" => DateTime.to_iso8601(date_from)
    }
    |> FetchWorker.new(unique: [keys: [:organization_id, :subject_type], period: :infinity, states: :incomplete])
    |> Firmowid.Oban.insert(skip_organization_id: true)
  end

  # KSeF lists the invoices where the organization is the buyer (Subject2) or the seller (Subject1).
  defp subject_type(CostInvoice), do: "Subject2"
  defp subject_type(SalesInvoice), do: "Subject1"

  @doc """
  Returns whether an invoice fetch from KSeF is queued or running for the organization.
  """
  @spec fetching_invoices?(Scope.t()) :: boolean()
  def fetching_invoices?(scope) do
    # Oban.Job is not an Ash resource — raw Ecto query is required here.
    Oban.Job
    |> where(
      [j],
      j.worker == "Firmowid.Ksef.Workers.FetchWorker" and
        fragment("?->>'organization_id'", j.args) == ^scope.tenant and
        j.state in ["available", "scheduled", "executing", "retryable"]
    )
    |> Repo.exists?(oban_jobs: true)
  end

  @doc """
  Fetches FA XML invoice by KSeF number.
  Rate limit 64 req/h
  """
  @spec get_invoice_xml_by_ksef_number(String.t(), String.t()) ::
          {:ok, binary()} | {:error, term()}
  def get_invoice_xml_by_ksef_number(ksef_number, organization_id) when is_binary(ksef_number) do
    access_token = SessionWorker.get_access_token!(organization_id)
    ApiClient.get_invoice_xml(access_token, ksef_number)
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
  @spec submit_sales_invoice(Ash.UUID.t(), Scope.t()) ::
          {:ok, Oban.Job.t()}
          | {:error,
             :not_authenticated
             | :invoice_not_found
             | :invoice_is_draft
             | :invoice_already_locked
             | Ash.Error.t()
             | {:invalid_for_ksef, list()}}
  def submit_sales_invoice(sales_invoice_id, scope) do
    with :ok <- validate_ksef_authenticated(scope),
         {:ok, invoice} <- validate_invoice_for_submission(sales_invoice_id, scope) do
      %{
        "action" => "submit",
        "organization_id" => scope.tenant,
        "sales_invoice_id" => invoice.id
      }
      |> SubmissionWorker.new()
      |> Firmowid.Oban.insert(skip_organization_id: true)
    end
  end

  defp validate_ksef_authenticated(scope) do
    case connection_status(scope: scope) do
      {:ok, %{status: :connected}} -> :ok
      {:ok, _status} -> {:error, :not_authenticated}
      {:error, _error} = error -> error
    end
  end

  defp validate_invoice_for_submission(sales_invoice_id, scope) do
    opts = [scope: scope]

    case SalesInvoice.by_id(sales_invoice_id, opts) do
      {:ok, nil} ->
        {:error, :invoice_not_found}

      {:ok, invoice} ->
        with :ok <- authorize_invoice_submission(invoice, scope) do
          validate_invoice_state(invoice)
        end

      {:error, _error} = error ->
        error
    end
  end

  defp authorize_invoice_submission(invoice, scope) do
    case Ash.can({invoice, :start_ksef_submission}, scope,
           maybe_is: false,
           return_forbidden_error?: true
         ) do
      {:ok, true} -> :ok
      {:ok, false, error} -> {:error, Ash.Error.to_error_class(error)}
      {:error, error} -> {:error, error}
    end
  end

  defp validate_invoice_state(invoice) do
    cond do
      is_nil(invoice.invoice_number) ->
        {:error, :invoice_is_draft}

      not is_nil(invoice.ksef_number) or not is_nil(invoice.locked_at) ->
        {:error, :invoice_already_locked}

      true ->
        validate_ksef_required_fields(invoice)
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
  def invoice_url!(invoice), do: invoice_url!(invoice, [])

  @spec invoice_url!(map(), keyword()) :: String.t()
  def invoice_url!(%CostInvoice{ksef_number: nil}, _opts) do
    raise ArgumentError, "Cannot generate KSeF URL for non-KSeF-imported cost invoice"
  end

  def invoice_url!(%CostInvoice{seller_nip: seller_nip, issue_date: issue_date} = invoice, opts) do
    invoice = Ash.load!(invoice, [:blob], opts)

    checksum =
      invoice.blob.blob_checksum
      |> Base.decode16!(case: :lower)
      |> Base.url_encode64(padding: false)

    invoice_url(seller_nip, issue_date, checksum)
  end

  def invoice_url!(%{seller_nip: seller_nip, issue_date: issue_date, ksef_number: ksef_number} = invoice, _opts)
      when not is_nil(ksef_number) do
    checksum = invoice.ksef_invoice_checksum || backfill_ksef_checksum!(invoice)
    invoice_url(seller_nip, issue_date, checksum)
  end

  defp invoice_url(seller_nip, issue_date, checksum) do
    base_url = Application.get_env(:firmowid, :ksef)[:qr_code_base_url]
    issue_date = Calendar.strftime(issue_date, "%d-%m-%Y")
    safe_checksum = URI.encode_www_form(checksum)
    path = "/invoice/#{seller_nip}/#{issue_date}/#{safe_checksum}"

    base_url
    |> URI.new!()
    |> URI.append_path(path)
    |> to_string()
  end

  defp backfill_ksef_checksum!(%{ksef_number: ksef_number, organization_id: organization_id} = invoice) do
    invoice_xml =
      case get_invoice_xml_by_ksef_number(ksef_number, organization_id) do
        {:ok, xml} ->
          xml

        {:error, reason} ->
          raise RuntimeError,
                "Failed to fetch KSeF invoice XML for checksum backfill (ksef_number: #{ksef_number}): #{inspect(reason)}"
      end

    checksum = compute_fa3_checksum(invoice_xml)

    scope = %Scope{
      actor: %SystemActor{org_id: organization_id, role: :ksef_session},
      tenant: organization_id
    }

    SalesInvoice.record_ksef_submission!(invoice, %{ksef_invoice_checksum: checksum}, scope: scope)

    checksum
  end

  @doc "Computes SHA-256 checksum of FA(3) XML content, URL-safe base64 encoded."
  @spec compute_fa3_checksum(binary()) :: String.t()
  def compute_fa3_checksum(xml_content) when is_binary(xml_content) do
    :sha256
    |> :crypto.hash(xml_content)
    |> Base.url_encode64(padding: false)
  end

  @doc """
  Returns a shorter message for cases when the correction was deleted by the worker.
  """
  @spec failed_correction_deleted_message() :: String.t()
  def failed_correction_deleted_message do
    gettext("Could not send the correction to KSeF. The correction was deleted — fix the data and try again.")
  end
end
