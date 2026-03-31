defmodule Firmowid.Ksef.FetchWorker do
  @moduledoc false
  use Oban.Worker,
    queue: :ksef_fetch,
    max_attempts: 3

  import Ecto.Query
  import Firmowid.Ksef.ApiClient, only: [parse_datetime!: 1]

  alias Firmowid.Ash.Blobs.Blob, as: AshBlob
  alias Firmowid.Ash.Invoicing.CostInvoice, as: AshCostInvoice
  alias Firmowid.CostInvoices.OpenAIEnrichment
  alias Firmowid.Ksef.ApiClient
  alias Firmowid.Ksef.Encryption
  alias Firmowid.Ksef.InvoiceParser
  alias Firmowid.Ksef.SessionWorker
  alias Firmowid.Repo

  require Logger

  @impl Oban.Worker
  def perform(%{args: %{"action" => action, "organization_id" => organization_id} = args}) do
    Repo.put_org_id(organization_id)

    case action do
      "initiate_export" -> initiate_export(args)
      "poll_export" -> poll_export(args)
    end
  end

  def initiate_export(args) do
    date_from = parse_datetime!(args["date_from"])
    encryption_data = Encryption.generate_encryption_data()

    case perform_initiate_export(date_from, encryption_data) do
      {:ok, reference_number} ->
        schedule_poll_job(
          reference_number,
          encryption_data
        )

      {:error, reason} = error ->
        Logger.error("Failed to initiate KSeF export: #{inspect(reason)}")
        error
    end
  end

  def poll_export(%{"reference_number" => reference_number} = args) do
    session = SessionWorker.get_access_token!()

    case ApiClient.get_export_status(session, reference_number) do
      {:ok, package} ->
        process_downloaded_package(package, args)

      :pending ->
        {:snooze, 30}

      {:error, reason} = error ->
        Logger.error("Failed to poll KSeF export: #{inspect(reason)}")
        error
    end
  end

  @impl Oban.Worker
  def backoff(%Oban.Job{} = job) do
    corrected_attempt = 3 - (job.max_attempts - job.attempt)

    Oban.Worker.backoff(%{job | attempt: corrected_attempt})
  end

  defp perform_initiate_export(date_from, encryption_data) do
    filters = %{
      # Subject2 means cost invoices
      "subjectType" => "Subject2",
      "dateRange" => %{
        "dateType" => "PermanentStorage",
        "from" => DateTime.to_iso8601(date_from)
      }
    }

    encryption_data = %{
      "encryptedSymmetricKey" => encryption_data.key |> Encryption.encrypt_symmetric_key() |> Base.encode64(),
      "initializationVector" => Base.encode64(encryption_data.iv)
    }

    session = SessionWorker.get_access_token!()
    ApiClient.initiate_invoice_export(session, filters, encryption_data)
  end

  defp process_downloaded_package(%{"parts" => []}, _args) do
    Logger.info("KSeF export completed with no invoices to download")
    {:ok, 0}
  end

  defp process_downloaded_package(package, args) do
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

    result = create_cost_invoices_from_package(metadata, invoices)

    if package["isTruncated"] do
      schedule_next_fetch(package["lastPermanentStorageDate"])
    end

    result
  end

  defp download_and_decrypt_parts!(parts, key, iv) do
    parts
    |> Enum.map(fn part ->
      expiration_date = parse_datetime!(part["expirationDate"])

      if DateTime.before?(expiration_date, DateTime.utc_now()) do
        raise "Package part #{part["ordinalNumber"]} has expired on #{expiration_date}"
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
      timeout: :infinity
    )
    |> Stream.map(fn
      {:ok, body} -> body
      {:exit, reason} -> raise("Failed to download package part: #{inspect(reason)}")
    end)
    |> Enum.to_list()
  end

  defp concatenate_parts(parts), do: IO.iodata_to_binary(parts)

  defp unzip_package!(zip_binary) when is_binary(zip_binary) do
    case :zip.unzip(zip_binary, [:memory]) do
      {:ok, files} -> Enum.map(files, fn {filename, content} -> {to_string(filename), content} end)
      {:error, reason} -> raise "Failed to unzip KSeF package: #{inspect(reason)}"
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
      raise "Checksum mismatch for downloaded part"
    end
  end

  defp create_cost_invoices_from_package(metadata_json, invoice_files) do
    metadata_by_ksef_number = parse_metadata_json(metadata_json)

    ksef_numbers = Map.keys(metadata_by_ksef_number)

    Logger.info("KSeF invoice numbers from export: #{inspect(ksef_numbers)}")

    existing_invoices =
      CostInvoices.CostInvoice
      |> where([c], c.ksef_number in ^ksef_numbers)
      |> select([c], c.ksef_number)
      |> Repo.all()
      |> MapSet.new()

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

    downloaded_invoices
    |> Enum.map(fn {ksef_number, xml_content} ->
      metadata = Map.fetch!(metadata_by_ksef_number, ksef_number)

      create_cost_invoice_from_xml(ksef_number, xml_content, metadata)
    end)
    |> accumulate_errors()
  end

  defp accumulate_errors(results) do
    Enum.reduce(results, :ok, fn
      :ok, acc -> acc
      {:ok, _}, acc -> acc
      {:error, error}, :ok -> {:error, [error]}
      {:error, error}, {:error, errors} -> {:error, [error | errors]}
    end)
  end

  defp parse_metadata_json(metadata_json) do
    metadata_json
    |> Jason.decode!()
    |> Map.fetch!("invoices")
    |> Map.new(fn invoice -> {invoice["ksefNumber"], invoice} end)
  end

  defp create_cost_invoice_from_xml(ksef_number, xml_content, ksef_metadata) do
    with {:ok, attrs} <- InvoiceParser.parse(xml_content),
         attrs = enrich_cost_invoice_with_metadata(attrs, ksef_number, ksef_metadata),
         {:ok, path} <- write_to_temp_file(xml_content, "#{ksef_number}.xml") do
      # TODO: replace authorize?: false + actor: %{} with system actor once available
      blob_opts = [tenant: Repo.get_org_id(), authorize?: false, actor: %{}]

      case AshBlob.create_blob(path, "application/xml", "#{ksef_number}.xml", blob_opts) do
        {:ok, blob} ->
          Logger.info("Creating cost invoice #{ksef_number} from #{ksef_number}.xml")

          try do
            # CostInvoice.create_cost_invoice/1 doesn't return result tuple. It raises on failure
            attrs
            |> Map.put(:blob_id, blob.id)
            |> AshCostInvoice.create_cost_invoice()

            :ok
          rescue
            # on failure, clean up dangling blob from DB and S3
            error ->
              AshBlob.destroy_blob!(blob.id, blob_opts)

              AshCostInvoice.broadcast_cost_invoice_failed_to_process(
                "#{ksef_number}.xml",
                Repo.get_org_id()
              )

              ErrorTracker.report(error, __STACKTRACE__)

              {:error, "Failed to create cost invoice from XML #{ksef_number}.xml: #{inspect(error)}"}
          end

        {:error,
         %Ecto.Changeset{
           changes: %{blob_checksum: _blob_checksum},
           errors: [blob_checksum: {"has already been taken", _}]
         }} ->
          Logger.error("Duplicate blob detected for #{ksef_number}.xml, skipping invoice creation")
          :ok

        {:error, reason} ->
          {:error, "Failed to upload cost invoice from XML #{ksef_number}.xml: #{inspect(reason)}"}
      end
    else
      {:error, reason} ->
        {:error, "Failed to create cost invoice from XML #{ksef_number}.xml: #{inspect(reason)}"}
    end
  end

  defp enrich_cost_invoice_with_metadata(attrs, ksef_number, ksef_metadata) do
    attrs
    |> Map.update!(:total_amount, &Decimal.negate(&1))
    |> Map.put(:ksef_number, ksef_number)
    |> Map.put(:ksef_permanent_storage_date, parse_datetime!(ksef_metadata["permanentStorageDate"]))
    |> Map.put(:ksef_downloaded_at, DateTime.utc_now())
    |> Map.put(:organization_id, Repo.get_org_id())
    |> Map.put(
      :description,
      OpenAIEnrichment.generate_description(%{"seller" => attrs.seller, "items_list" => attrs.items_list})
    )
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

  defp schedule_poll_job(reference_number, encryption_data) do
    %{
      "action" => "poll_export",
      "organization_id" => Repo.get_org_id(),
      "reference_number" => reference_number,
      "encryption_key" => Base.encode64(encryption_data.key),
      "encryption_iv" => Base.encode64(encryption_data.iv)
    }
    |> new(schedule_in: 15)
    |> Firmowid.Oban.insert()
  end

  defp schedule_next_fetch(last_permanent_storage_date) do
    Logger.info("Scheduling next KSeF fetch starting from #{last_permanent_storage_date}")

    %{
      "action" => "initiate_export",
      "organization_id" => Repo.get_org_id(),
      "date_from" => last_permanent_storage_date
    }
    |> new()
    |> Firmowid.Oban.insert()
  end
end
