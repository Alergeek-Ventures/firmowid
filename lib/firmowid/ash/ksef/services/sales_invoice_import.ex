defmodule Firmowid.Ash.Ksef.Services.SalesInvoiceImport do
  @moduledoc """
  Records sales invoices from a KSeF export package that were issued outside Firmowid.

  The export also lists the invoices Firmowid itself submitted. Those are recognized
  by their KSeF number, or by their invoice number while the submission still awaits
  KSeF's confirmation, and only their storage date is kept so the next import starts
  after them. An invoice the sales invoice cannot represent or accept is skipped, so it
  does not hold back the rest of the package, and returned as a `SkippedInvoicesError`
  that fails the job and reaches Sentry. Any other failure fails the job right away,
  which retries the package before the next import can start after it.
  """

  import Firmowid.Ash.Ksef.Services.ApiClient, only: [parse_datetime!: 1]

  alias Ash.Error.Invalid
  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Ksef
  alias Firmowid.Ash.Ksef.Services.SalesInvoiceParser
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor
  alias Firmowid.ErrorKind

  require Ash.Query

  defmodule SkippedInvoicesError do
    @moduledoc "KSeF sales invoices an import skipped, with the reason for each."

    defexception [:skipped]

    @type t :: %__MODULE__{skipped: [%{ksef_number: String.t(), reason: String.t()}]}

    @impl true
    def message(%{skipped: skipped}) do
      "Skipped #{length(skipped)} KSeF sales invoice(s) Firmowid cannot import: " <>
        Enum.map_join(skipped, "; ", &"#{&1.ksef_number} (#{&1.reason})")
    end
  end

  @doc """
  Imports the package's invoices for the scope's organization and returns counts of
  `created`, `skipped_known` and `skipped_unsupported` invoices, with the KSeF number and
  reason of each unsupported one in `skipped`.

  `metadata` maps each KSeF number to its export metadata, `invoices` holds
  `{"<ksef number>.xml", xml}` entries.
  """
  @spec import_package(%{String.t() => map()}, [{String.t(), binary()}], Scope.t()) :: map()
  def import_package(metadata, invoices, %Scope{tenant: organization_id}) do
    scope = %Scope{
      actor: %SystemActor{org_id: organization_id, role: :sales_invoice_processor},
      tenant: organization_id
    }

    # In storage order, so a correction of a correction finds the one it corrects.
    parsed =
      invoices
      |> Enum.map(fn {filename, xml} ->
        ksef_number = String.replace_suffix(filename, ".xml", "")

        stored_at =
          metadata
          |> Map.fetch!(ksef_number)
          |> Map.fetch!("permanentStorageDate")
          |> parse_datetime!()

        {ksef_number, xml, SalesInvoiceParser.parse(xml), stored_at}
      end)
      |> Enum.sort_by(&elem(&1, 3), DateTime)

    known = known_invoices(parsed, scope)

    results =
      Enum.map(parsed, fn {ksef_number, xml, attrs, stored_at} ->
        import_invoice(ksef_number, xml, attrs, stored_at, known, scope)
      end)

    skipped = for {:skipped, invoice} <- results, do: invoice

    %{
      total_in_package: length(results),
      created: Enum.count(results, &(&1 == :created)),
      skipped_known: Enum.count(results, &(&1 == :known)),
      skipped_unsupported: length(skipped),
      skipped: skipped
    }
  end

  defp known_invoices(parsed, scope) do
    ksef_numbers = Enum.map(parsed, &elem(&1, 0))

    invoice_numbers =
      for {_ksef_number, _xml, {:ok, %{invoice_number: number}}, _stored_at} <- parsed,
          number,
          do: number

    SalesInvoice
    |> Ash.Query.filter(ksef_number in ^ksef_numbers or invoice_number in ^invoice_numbers)
    |> then(&SalesInvoice.list!(scope: scope, query: &1))
  end

  defp import_invoice(ksef_number, xml, attrs, stored_at, known, scope) do
    case Enum.find(known, &(&1.ksef_number == ksef_number)) do
      %SalesInvoice{} = own ->
        record_storage_date(own, stored_at, scope)

      nil ->
        with {:ok, attrs} <- attrs,
             :ok <- check_number_free(attrs.invoice_number, known),
             {:ok, _invoice} <- create(attrs, ksef_number, xml, stored_at, scope) do
          :created
        else
          :own_pending ->
            :known

          {:error, reason} ->
            {:skipped, %{ksef_number: ksef_number, reason: skip_reason(reason)}}
        end
    end
  end

  # An invoice Firmowid submitted is numbered and locked before KSeF assigns its KSeF number.
  defp check_number_free(invoice_number, known) do
    case Enum.find(known, &(&1.invoice_number == invoice_number)) do
      nil ->
        :ok

      %SalesInvoice{ksef_number: nil, locked_at: locked_at} when not is_nil(locked_at) ->
        :own_pending

      %SalesInvoice{} ->
        {:error, :invoice_number_taken}
    end
  end

  defp record_storage_date(%SalesInvoice{ksef_permanent_storage_date: nil} = invoice, stored_at, scope) do
    Invoicing.record_sales_invoice_ksef_submission!(
      invoice,
      %{ksef_permanent_storage_date: DateTime.to_naive(stored_at)},
      scope: scope
    )

    :known
  end

  defp record_storage_date(%SalesInvoice{}, _stored_at, _scope), do: :known

  # KSeF stored the invoice when it was issued, so it is locked from then on like a confirmed one.
  defp create(attrs, ksef_number, xml, stored_at, scope) do
    attrs
    |> Map.merge(%{
      ksef_number: ksef_number,
      ksef_invoice_checksum: Ksef.compute_fa3_checksum(xml),
      ksef_permanent_storage_date: DateTime.to_naive(stored_at),
      locked_at: DateTime.truncate(stored_at, :second),
      item_names: Enum.map_join(attrs.sales_invoice_items, " ", & &1.name)
    })
    |> Invoicing.import_sales_invoice_from_ksef(scope: scope)
    |> case do
      {:ok, invoice} -> {:ok, invoice}
      {:error, %Invalid{} = error} -> {:error, error}
      {:error, error} -> raise error
    end
  end

  defp skip_reason({:unsupported, reason}), do: reason
  defp skip_reason(:invoice_number_taken), do: "invoice number already used in Firmowid"

  defp skip_reason(%Invalid{errors: errors}) do
    Enum.map_join(errors, ", ", &"#{Map.get(&1, :field)}: #{Exception.message(&1)}")
  end

  defp skip_reason(reason), do: ErrorKind.classify(reason)
end
