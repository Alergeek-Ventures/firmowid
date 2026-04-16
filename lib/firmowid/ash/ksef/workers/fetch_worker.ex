defmodule Firmowid.Ash.Ksef.Workers.FetchWorker do
  @moduledoc """
  Oban worker for fetching cost invoices from KSeF.

  Manages the two-phase fetch lifecycle:
  1. `initiate_export` — requests an encrypted export of cost invoices from KSeF
  2. `poll_export` — polls for export readiness, downloads encrypted package parts,
     decrypts, unzips, parses FA(3) XML, and creates `CostInvoice` records

  ## Reliability guarantees

  - Uses `restrictToPermanentStorageHwmDate = true` to activate KSeF's HWM
    (High Water Mark) completeness guarantee — exports only include invoices up
    to a point where KSeF guarantees no new invoices will appear.
  - For truncated exports, the next-page fetch is scheduled **before** processing
    invoices, so a mid-processing crash won't lose the continuation point.
  - If any invoice in a batch fails to parse or create, the **entire batch fails**
    and will be retried — no silent cursor advancement past failed invoices.
  - Individual invoice failures are reported to Sentry with full context.
  - Polling is bounded to 120 snoozes (~60 minutes) to prevent indefinite polling.
  """
  use Oban.Worker,
    queue: :ksef_fetch,
    max_attempts: 3

  import Firmowid.Ash.Ksef.Services.ApiClient, only: [parse_datetime!: 1]

  alias Ash.Error.Invalid
  alias Firmowid.Ash.Blobs
  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Ksef.Services.ApiClient
  alias Firmowid.Ash.Ksef.Services.Encryption
  alias Firmowid.Ash.Ksef.Services.InvoiceParser
  alias Firmowid.Ash.Ksef.Workers.SessionWorker
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor

  require Ash.Query
  require Logger

  @snooze_seconds 30
  @max_snooze_count 120
  @worker_max_attempts 3

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

    case perform_initiate_export(date_from, encryption_data, organization_id) do
      {:ok, reference_number} ->
        schedule_poll_job(
          reference_number,
          encryption_data,
          organization_id,
          args["date_from"]
        )

      {:error, reason} = error ->
        Logger.error("Failed to initiate KSeF export: #{inspect(reason)}")
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

      {:error, reason} = error ->
        Logger.error("Failed to poll KSeF export: #{inspect(reason)}")
        error
    end
  end

  # In OSS Oban, {:snooze, N} increments both attempt and max_attempts.
  # We use the job's attempt field to track how many times we've polled.
  # The initial attempt is 1, so after @max_snooze_count snoozes, attempt will
  # be @max_snooze_count + 1 (accounting for the original max_attempts offset).
  defp handle_pending_poll(%{max_attempts: max_attempts}, _scope) do
    snooze_count = max_attempts - @worker_max_attempts

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
      %{"date_from" => args["date_from"], "organization_id" => scope.tenant},
      scope.tenant
    )
  end

  defp perform_initiate_export(date_from, encryption_data, organization_id) do
    filters = %{
      # Subject2 means cost invoices
      "subjectType" => "Subject2",
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
    # Schedule next-page fetch BEFORE processing invoices.
    # This ensures continuation is not lost if the worker is killed mid-processing.
    schedule_continuation_fetch(package, scope.tenant)

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

    create_cost_invoices_from_package(metadata, invoices, scope, job, is_truncated)
  end

  defp schedule_continuation_fetch(package, organization_id) do
    if package["isTruncated"] do
      schedule_next_fetch(package["lastPermanentStorageDate"], organization_id)
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
      {:ok, body} -> body
      {:exit, reason} -> raise RuntimeError, "Failed to download package part: #{inspect(reason)}"
    end)
    |> Enum.to_list()
  end

  defp concatenate_parts(parts), do: IO.iodata_to_binary(parts)

  defp unzip_package!(zip_binary) when is_binary(zip_binary) do
    case :zip.unzip(zip_binary, [:memory]) do
      {:ok, files} ->
        Enum.map(files, fn {filename, content} -> {to_string(filename), content} end)

      {:error, reason} ->
        raise RuntimeError, "Failed to unzip KSeF package: #{inspect(reason)}"
    end
  end

  # sobelow_skip ["DOS.StringToAtom"]
  # Value is part["method"] from the KSeF API response — always "GET" or "POST",
  # not user-controlled. Req.request!/1 requires an atom for the :method option.
  defp download_part(part) do
    method = part["method"] |> String.downcase() |> String.to_atom()

    checksum =
      part["encryptedPartHash"]
      |> Base.decode64!()
      |> Base.encode16(case: :lower)

    Req.request!(
      url: part["url"],
      method: method,
      checksum: "sha256:#{checksum}",
      http_errors: :raise,
      retry: :transient
    ).body
  end

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

    Logger.info("KSeF invoice numbers from export: #{inspect(ksef_numbers)}")

    existing_invoices =
      CostInvoice
      |> Ash.Query.filter(ksef_number in ^ksef_numbers)
      |> Ash.Query.select([:ksef_number])
      |> Ash.read!(scope: scope)
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
      "KSeF invoice download results: downloaded=#{inspect(Enum.map(downloaded_invoices, &elem(&1, 0)))} " <>
        "rejected=#{inspect(Enum.map(rejected_invoices, &elem(&1, 0)))}"
    )

    results =
      Enum.map(downloaded_invoices, fn {ksef_number, xml_content} ->
        metadata = Map.fetch!(metadata_by_ksef_number, ksef_number)

        case create_cost_invoice_from_xml(ksef_number, xml_content, metadata, scope) do
          :ok ->
            :ok

          {:error, reason} = error ->
            report_invoice_failure(ksef_number, reason, scope.tenant)
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

        {:error, "Failed to process #{length(errors)} invoice(s): #{Enum.map_join(errors, "; ", &inspect/1)}"}
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
    Oban.update_job(job.id, fn job ->
      %{meta: Map.merge(job.meta, summary)}
    end)
  end

  defp report_invoice_failure(ksef_number, reason, organization_id) do
    Logger.error("KSeF invoice processing failed for #{ksef_number} (org: #{organization_id}): #{inspect(reason)}")

    Sentry.capture_message(
      "KSeF invoice processing failed",
      tags: %{ksef_number: ksef_number, organization_id: organization_id},
      extra: %{reason: inspect(reason)}
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
        {:error, "Failed to create cost invoice from XML #{ksef_number}.xml: #{inspect(reason)}"}
    end
  end

  defp enrich_cost_invoice_with_metadata(attrs, ksef_number, ksef_metadata, organization_id) do
    attrs
    |> Map.update!(:total_amount, &Decimal.negate(&1))
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

  defp schedule_poll_job(reference_number, encryption_data, organization_id, date_from) do
    %{
      "action" => "poll_export",
      "organization_id" => organization_id,
      "reference_number" => reference_number,
      "encryption_key" => Base.encode64(encryption_data.key),
      "encryption_iv" => Base.encode64(encryption_data.iv),
      "date_from" => date_from
    }
    |> new(schedule_in: 15)
    |> Firmowid.Oban.insert(skip_organization_id: true)
  end

  defp schedule_next_fetch(last_permanent_storage_date, organization_id) do
    Logger.info("Scheduling next KSeF fetch starting from #{last_permanent_storage_date}")

    %{
      "action" => "initiate_export",
      "organization_id" => organization_id,
      "date_from" => last_permanent_storage_date
    }
    |> new()
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
      {:error, "Failed to upload cost invoice from XML #{ksef_number}.xml: #{inspect(error)}"}
    end
  end

  defp handle_blob_upload_result({:error, reason}, ksef_number, _attrs, _blob_opts, _path) do
    {:error, "Failed to upload cost invoice from XML #{ksef_number}.xml: #{inspect(reason)}"}
  end

  defp handle_duplicate_blob(ksef_number, attrs, blob_opts, path) do
    scope = Keyword.fetch!(blob_opts, :scope)
    checksum = compute_checksum(path)

    case Blobs.find_blob_with_cost_invoice(checksum, scope: scope) do
      {:ok, _blob, %CostInvoice{}} ->
        Logger.info("KSeF invoice #{ksef_number} already has a cost invoice, skipping")
        :ok

      {:ok, blob, nil} ->
        Logger.info("Found orphan blob for #{ksef_number}, creating cost invoice")
        create_cost_invoice_for_blob(blob, ksef_number, attrs, blob_opts)

      {:error, :not_found} ->
        {:error, "Duplicate blob conflict for #{ksef_number}.xml but blob not found by checksum"}
    end
  end

  defp create_cost_invoice_for_blob(blob, ksef_number, attrs, blob_opts) do
    Logger.info("Creating cost invoice #{ksef_number} from #{ksef_number}.xml")

    try do
      attrs
      |> Map.put(:blob_id, blob.id)
      |> Invoicing.create_cost_invoice()

      :ok
    rescue
      error ->
        scoped_blob_opts = with_blob_scope(blob, blob_opts)

        Blobs.destroy_blob!(
          blob,
          Keyword.put(scoped_blob_opts, :notification_metadata, %{reason: :processing_failed})
        )

        {:error, "Failed to create cost invoice from XML #{ksef_number}.xml: #{Exception.message(error)}"}
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

  defp with_blob_scope(blob, blob_opts) do
    scope = Keyword.fetch!(blob_opts, :scope)
    actor = Map.put(scope.actor, :blob_id, blob.id)
    Keyword.put(blob_opts, :scope, %{scope | actor: actor})
  end
end
