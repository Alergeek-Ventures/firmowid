# credo:disable-for-this-file ExDNA.Credo
# Export polling, pagination, decryption, and invoice ingestion intentionally share repeated
# reliability patterns; deduplicating safely requires broader worker/service boundary extraction.
defmodule Firmowid.Ksef.Workers.FetchWorker do
  @moduledoc """
  Oban worker for fetching invoices from KSeF.

  The `subject_type` argument selects the organization's side of the invoices:
  `Subject2` (buyer, the default) imports cost invoices, `Subject1` (seller) imports
  sales invoices issued outside Firmowid through `SalesInvoiceImport`.

  Manages the two-phase fetch lifecycle:
  1. `initiate_export` — requests an encrypted export of the organization's invoices from KSeF
  2. `poll_export` — polls for export readiness, downloads encrypted package parts,
     decrypts, unzips, parses FA(3) XML, and creates `CostInvoice` or `SalesInvoice` records

  ## Reliability guarantees

  - Uses `restrictToPermanentStorageHwmDate = true` to activate KSeF's HWM
    (High Water Mark) completeness guarantee — exports only include invoices up
    to a point where KSeF guarantees no new invoices will appear.
  - For truncated cost-invoice exports, the next-page fetch is scheduled **before**
    processing invoices, so a mid-processing crash won't lose the continuation point.
    Sales-invoice pages schedule it **after** they are saved, so a correction on the next
    page finds its original; a page that crashes is retried and schedules it then.
  - If any cost invoice in a batch fails to parse or create, the **entire batch fails**
    and will be retried — no silent cursor advancement past failed invoices. Sales
    invoices import the documents they can represent and then fail the batch with the
    skipped ones, or fail it right away on any other error (see `SalesInvoiceImport`).
  - Individual invoice failures are reported to Sentry with full context.
  - Polling is bounded to 120 snoozes (~60 minutes) to prevent indefinite polling.
  """
  use Oban.Worker,
    queue: :ksef_fetch,
    max_attempts: 3

  import Firmowid.Ksef.Services.ApiClient, only: [parse_datetime!: 1]

  alias Ash.Error.Invalid
  alias Firmowid.Blobs
  alias Firmowid.ErrorKind
  alias Firmowid.Invoicing
  alias Firmowid.Invoicing.CostInvoice
  alias Firmowid.Ksef.Services.ApiClient
  alias Firmowid.Ksef.Services.Encryption
  alias Firmowid.Ksef.Services.InvoiceParser
  alias Firmowid.Ksef.Services.SalesInvoiceImport
  alias Firmowid.Ksef.Workers.SessionWorker
  alias Firmowid.Scope
  alias Firmowid.SystemActor

  require Ash.Query
  require Logger

  @snooze_seconds 30
  @max_snooze_count 120

  @impl Oban.Worker
  def timeout(_job), do: to_timeout(minute: 20)

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: Oban.Worker.result()
  def perform(%{args: %{"action" => action, "organization_id" => organization_id} = args} = job) do
    actor = %SystemActor{org_id: organization_id, role: :ksef_session}
    scope = %Scope{actor: actor, tenant: organization_id}

    case action do
      "initiate_export" -> initiate_export(args, organization_id)
      "poll_export" -> poll_export(args, scope, job)
    end
  end

  defp initiate_export(args, organization_id) do
    date_from = parse_datetime!(args["date_from"])
    encryption_data = Encryption.generate_encryption_data()

    case perform_initiate_export(date_from, subject_type(args), encryption_data, organization_id) do
      {:ok, reference_number} ->
        schedule_poll_job(
          reference_number,
          encryption_data,
          organization_id,
          args["date_from"],
          subject_type(args)
        )

      {:error, _reason} = error ->
        error
    end
  end

  defp poll_export(%{"reference_number" => reference_number} = args, scope, job) do
    session = SessionWorker.get_access_token!(scope.tenant)

    case ApiClient.get_export_status(session, reference_number) do
      {:ok, package} ->
        process_downloaded_package(package, args, scope, job)

      :pending ->
        handle_pending_poll(job, scope)

      {:error, :expired} ->
        handle_expired_export(args, scope)

      {:error, _reason} = error ->
        error
    end
  end

  # A snooze does not use up an attempt; Oban counts snoozes in the job's meta.
  defp handle_pending_poll(job, _scope) do
    snooze_count = Map.get(job.meta, "snoozed", 0)

    if snooze_count >= @max_snooze_count do
      {:error,
       "KSeF export polling exceeded maximum #{@max_snooze_count} snoozes (~#{div(@max_snooze_count * @snooze_seconds, 60)} minutes)"}
    else
      {:snooze, @snooze_seconds}
    end
  end

  defp handle_expired_export(args, scope) do
    Logger.warning("KSeF export expired, re-initiating from #{args["date_from"]}")

    # Re-initiate the export from the original date_from instead of retrying the expired reference
    initiate_export(
      %{
        "date_from" => args["date_from"],
        "organization_id" => scope.tenant,
        "subject_type" => subject_type(args)
      },
      scope.tenant
    )
  end

  # Jobs queued before sales invoice imports carry no subject type and fetch cost invoices.
  defp subject_type(args), do: Map.get(args, "subject_type", "Subject2")

  defp perform_initiate_export(date_from, subject_type, encryption_data, organization_id) do
    filters = %{
      "subjectType" => subject_type,
      "dateRange" => %{
        "dateType" => "PermanentStorage",
        "from" => DateTime.to_iso8601(date_from),
        "restrictToPermanentStorageHwmDate" => true
      }
    }

    encryption_data = %{
      "encryptedSymmetricKey" => encryption_data.key |> Encryption.encrypt_symmetric_key() |> Base.encode64(),
      "initializationVector" => Base.encode64(encryption_data.iv)
    }

    session = SessionWorker.get_access_token!(organization_id)
    ApiClient.initiate_invoice_export(session, filters, encryption_data)
  end

  defp process_downloaded_package(%{"parts" => []}, _args, _scope, job) do
    Logger.info("KSeF export completed with no invoices to download")

    stamp_job_meta(job, %{
      total_in_package: 0,
      created: 0,
      skipped_duplicate: 0,
      is_truncated: false
    })

    :ok
  end

  defp process_downloaded_package(package, args, scope, job) do
    encryption_key = Base.decode64!(args["encryption_key"])
    encryption_iv = Base.decode64!(args["encryption_iv"])

    files =
      package["parts"]
      |> download_and_decrypt_parts!(encryption_key, encryption_iv)
      |> concatenate_parts()
      |> unzip_package!()

    metadata =
      Enum.find_value(files, fn
        {"_metadata.json", metadata} -> metadata
        {_name, _content} -> nil
      end)

    invoices = Enum.filter(files, fn {name, _} -> String.ends_with?(name, ".xml") end)
    is_truncated = package["isTruncated"] == true

    case subject_type(args) do
      "Subject2" ->
        # Scheduled BEFORE processing, so a worker killed mid-processing keeps the continuation.
        schedule_continuation_fetch(package, args, scope.tenant)
        create_cost_invoices_from_package(metadata, invoices, scope, job, is_truncated)

      "Subject1" ->
        summary =
          SalesInvoiceImport.import_package(parse_metadata_json(metadata), invoices, scope)

        stamp_job_meta(job, Map.put(summary, :is_truncated, is_truncated))

        # Scheduled AFTER this page is saved, so corrections on the next page find their originals.
        # A job that fails before this point is retried and schedules it then.
        schedule_continuation_fetch(package, args, scope.tenant)

        case summary.skipped do
          [] -> :ok
          skipped -> {:error, %SalesInvoiceImport.SkippedInvoicesError{skipped: skipped}}
        end
    end
  end

  defp schedule_continuation_fetch(package, args, organization_id) do
    if package["isTruncated"] do
      {:ok, _job} =
        schedule_next_fetch(package["lastPermanentStorageDate"], args, organization_id)
    end
  end

  defp download_and_decrypt_parts!(parts, key, iv) do
    parts
    |> Enum.map(fn part ->
      expiration_date = parse_datetime!(part["expirationDate"])

      if DateTime.before?(expiration_date, DateTime.utc_now()) do
        raise RuntimeError,
              "Package part #{part["ordinalNumber"]} has expired on #{expiration_date}"
      end

      part
    end)
    |> Enum.sort_by(& &1["ordinalNumber"])
    |> Task.async_stream(
      fn part ->
        part
        |> download_part()
        |> Encryption.decrypt_aes256_cbc(key, iv)
        |> validate_part_checksum!(part)
      end,
      timeout: to_timeout(minute: 5)
    )
    |> Stream.map(fn
      {:ok, body} ->
        body

      {:exit, reason} ->
        raise RuntimeError,
              "Failed to download package part: error_kind=#{ErrorKind.classify(reason)}"
    end)
    |> Enum.to_list()
  end

  defp concatenate_parts(parts), do: IO.iodata_to_binary(parts)

  defp unzip_package!(zip_binary) when is_binary(zip_binary) do
    case :zip.unzip(zip_binary, [:memory]) do
      {:ok, files} ->
        Enum.map(files, fn {filename, content} -> {to_string(filename), content} end)

      {:error, reason} ->
        raise RuntimeError,
              "Failed to unzip KSeF package: error_kind=#{ErrorKind.classify(reason)}"
    end
  end

  defp download_part(part) do
    method = download_method(part["method"])
    request_options = Application.get_env(:firmowid, :ksef, [])[:request_options] || []

    checksum =
      part["encryptedPartHash"]
      |> Base.decode64!()
      |> Base.encode16(case: :lower)

    [
      url: part["url"],
      method: method,
      checksum: "sha256:#{checksum}",
      http_errors: :raise,
      retry: :transient
    ]
    |> Req.request!(request_options)
    |> Map.fetch!(:body)
  end

  defp download_method("GET"), do: :get
  defp download_method("POST"), do: :post

  defp validate_part_checksum!(data, part) do
    checksum = :crypto.hash(:sha256, data)
    part_hash = Base.decode64!(part["partHash"])

    if checksum == part_hash do
      data
    else
      raise RuntimeError, "Checksum mismatch for downloaded part #{part["ordinalNumber"]}"
    end
  end

  defp create_cost_invoices_from_package(metadata_json, invoice_files, scope, job, is_truncated) do
    metadata_by_ksef_number = parse_metadata_json(metadata_json)

    ksef_numbers = Map.keys(metadata_by_ksef_number)

    Logger.info("KSeF export metadata loaded: invoice_count=#{length(ksef_numbers)}")

    existing_invoices =
      CostInvoice
      |> Ash.Query.filter(ksef_number in ^ksef_numbers)
      |> Ash.Query.select([:ksef_number])
      |> then(&CostInvoice.list!(scope: scope, query: &1))
      |> MapSet.new(& &1.ksef_number)

    invoice_entries =
      Enum.map(invoice_files, fn {filename, xml} ->
        {String.replace_suffix(filename, ".xml", ""), xml}
      end)

    {downloaded_invoices, rejected_invoices} =
      Enum.split_with(invoice_entries, fn {ksef_number, _xml_content} ->
        not MapSet.member?(existing_invoices, ksef_number)
      end)

    Logger.info(
      "KSeF invoice download results: downloaded_count=#{length(downloaded_invoices)} " <>
        "rejected_count=#{length(rejected_invoices)}"
    )

    results =
      Enum.map(downloaded_invoices, fn {ksef_number, xml_content} ->
        metadata = Map.fetch!(metadata_by_ksef_number, ksef_number)

        case create_cost_invoice_from_xml(ksef_number, xml_content, metadata, scope) do
          :ok ->
            :ok

          {:error, reason} = error ->
            report_invoice_failure(reason, scope.tenant)
            error
        end
      end)

    errors = collect_errors(results)
    created_count = Enum.count(results, &(&1 == :ok))

    summary = %{
      total_in_package: length(invoice_entries),
      created: created_count,
      skipped_duplicate: length(rejected_invoices),
      failed: length(errors),
      is_truncated: is_truncated
    }

    case errors do
      [] ->
        stamp_job_meta(job, summary)
        :ok

      _ ->
        stamp_job_meta(job, summary)

        error_kinds = errors |> Enum.map(&ErrorKind.classify/1) |> Enum.uniq() |> Enum.join(",")
        {:error, "Failed to process #{length(errors)} invoice(s): error_kinds=#{error_kinds}"}
    end
  end

  defp collect_errors(results) do
    Enum.flat_map(results, fn
      :ok -> []
      {:ok, _} -> []
      {:error, error} -> [error]
    end)
  end

  defp stamp_job_meta(job, summary) do
    Logger.info(
      "KSeF invoice package processed",
      summary
      |> Map.take([
        :total_in_package,
        :created,
        :skipped_known,
        :skipped_unsupported,
        :skipped_duplicate,
        :failed,
        :is_truncated
      ])
      |> Map.to_list()
    )

    Oban.update_job(job.id, fn job ->
      %{meta: Map.merge(job.meta, summary)}
    end)
  end

  defp report_invoice_failure(reason, organization_id) do
    Logger.error(
      "KSeF invoice processing failed: organization_id=#{organization_id} " <>
        "error_kind=#{ErrorKind.classify(reason)}"
    )
  end

  defp parse_metadata_json(metadata_json) do
    metadata_json
    |> Jason.decode!()
    |> Map.fetch!("invoices")
    |> Map.new(fn invoice -> {invoice["ksefNumber"], invoice} end)
  end

  defp create_cost_invoice_from_xml(ksef_number, xml_content, ksef_metadata, scope) do
    with {:ok, attrs} <- InvoiceParser.parse(xml_content),
         attrs =
           enrich_cost_invoice_with_metadata(attrs, ksef_number, ksef_metadata, scope.tenant),
         {:ok, path} <- write_to_temp_file(xml_content, "#{ksef_number}.xml") do
      blob_opts = [scope: scope]

      path
      |> Blobs.create_blob("application/xml", "#{ksef_number}.xml", blob_opts)
      |> handle_blob_upload_result(ksef_number, attrs, blob_opts, path)
    else
      {:error, reason} ->
        {:error, "Failed to create cost invoice from XML: stage=parse error_kind=#{ErrorKind.classify(reason)}"}
    end
  end

  defp enrich_cost_invoice_with_metadata(attrs, ksef_number, ksef_metadata, organization_id) do
    attrs
    |> Map.update!(:amount, &Money.negate!/1)
    |> Map.put(:ksef_number, ksef_number)
    |> Map.put(
      :ksef_permanent_storage_date,
      parse_datetime!(ksef_metadata["permanentStorageDate"])
    )
    |> Map.put(:ksef_downloaded_at, DateTime.utc_now())
    |> Map.put(:organization_id, organization_id)
  end

  # sobelow_skip ["Traversal.FileModule"]
  # Path comes from Briefly.create/1 (OS-managed temp directory), not user input.
  defp write_to_temp_file(binary, original_filename) do
    extension = Path.extname(original_filename)

    with {:ok, path} <- Briefly.create(extname: extension),
         :ok <- File.write(path, binary) do
      {:ok, path}
    else
      {:error, reason} -> {:error, {:file_write_failed, reason}}
    end
  end

  defp schedule_poll_job(reference_number, encryption_data, organization_id, date_from, subject_type) do
    %{
      "action" => "poll_export",
      "organization_id" => organization_id,
      "subject_type" => subject_type,
      "reference_number" => reference_number,
      "encryption_key" => Base.encode64(encryption_data.key),
      "encryption_iv" => Base.encode64(encryption_data.iv),
      "date_from" => date_from
    }
    |> new(schedule_in: 15)
    |> Firmowid.Oban.insert(skip_organization_id: true)
  end

  # One continuation per export page: a retry of the page finds it already queued or done.
  defp schedule_next_fetch(last_permanent_storage_date, args, organization_id) do
    Logger.info("Scheduling next KSeF fetch starting from #{last_permanent_storage_date}")

    %{
      "action" => "initiate_export",
      "organization_id" => organization_id,
      "subject_type" => subject_type(args),
      "date_from" => last_permanent_storage_date,
      "continues" => args["reference_number"]
    }
    |> new(unique: [keys: [:continues], period: :infinity, states: :all])
    |> Firmowid.Oban.insert(skip_organization_id: true)
  end

  defp handle_blob_upload_result({:ok, blob}, ksef_number, attrs, blob_opts, _path) do
    create_cost_invoice_for_blob(blob, ksef_number, attrs, blob_opts)
  end

  defp handle_blob_upload_result({:error, error}, ksef_number, attrs, blob_opts, path)
       when is_struct(error, Invalid) or is_struct(error, Ecto.Changeset) do
    if blob_checksum_conflict?(error) do
      handle_duplicate_blob(ksef_number, attrs, blob_opts, path)
    else
      {:error, "Failed to upload cost invoice from XML: stage=upload error_kind=#{ErrorKind.classify(error)}"}
    end
  end

  defp handle_blob_upload_result({:error, reason}, _ksef_number, _attrs, _blob_opts, _path) do
    {:error, "Failed to upload cost invoice from XML: stage=upload error_kind=#{ErrorKind.classify(reason)}"}
  end

  defp handle_duplicate_blob(ksef_number, attrs, blob_opts, path) do
    scope = Keyword.fetch!(blob_opts, :scope)
    checksum = compute_checksum(path)

    case Blobs.find_blob_with_cost_invoice(checksum, scope: scope) do
      {:ok, _blob, %CostInvoice{ksef_number: existing_ksef_number}}
      when existing_ksef_number == ksef_number ->
        Logger.info("KSeF invoice already has a cost invoice, skipping")
        :ok

      {:ok, _blob, %CostInvoice{} = existing_invoice} ->
        {:error,
         "Checksum collision while creating cost invoice: stage=upload existing_invoice_id=#{existing_invoice.id}"}

      {:ok, blob, nil} ->
        Logger.info("Found orphan KSeF blob, creating cost invoice")
        create_cost_invoice_for_blob(blob, ksef_number, attrs, blob_opts)

      {:error, :not_found} ->
        {:error, "Duplicate blob conflict but blob not found by checksum"}
    end
  end

  defp create_cost_invoice_for_blob(blob, _ksef_number, attrs, _blob_opts) do
    Logger.info("Creating cost invoice from KSeF XML")

    case attrs |> Map.put(:blob_id, blob.id) |> Invoicing.create_cost_invoice_from_ksef() do
      {:ok, _cost_invoice} ->
        :ok

      {:error, reason} ->
        {:error, "Failed to create cost invoice from XML: stage=create error_kind=#{ErrorKind.classify(reason)}"}
    end
  end

  defp blob_checksum_conflict?(%Invalid{errors: errors}) when is_list(errors) do
    Enum.any?(errors, fn
      %Ash.Error.Changes.InvalidAttribute{
        field: :blob_checksum,
        message: "has already been taken"
      } ->
        true

      _ ->
        false
    end)
  end

  defp blob_checksum_conflict?(%Ecto.Changeset{errors: errors}) do
    Keyword.has_key?(errors, :blob_checksum)
  end

  defp blob_checksum_conflict?(_), do: false

  # sobelow_skip ["Traversal.FileModule"]
  # path comes from Briefly.create/1 (OS-managed temp directory), not user input.
  defp compute_checksum(upload_path) do
    upload_path
    |> Path.expand()
    |> File.stream!()
    |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
    |> :crypto.hash_final()
    |> Base.encode16()
    |> String.downcase()
  end
end
