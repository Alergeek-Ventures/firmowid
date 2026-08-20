defmodule Firmowid.Ash.Ksef.Workers.FetchWorkerTest do
  @moduledoc false
  use Firmowid.DataCase, async: false

  import Firmowid.AccountsFixtures
  import Firmowid.Test.Support.OpenAIEnrichmentTestHelpers

  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Ksef.Services.Encryption
  alias Firmowid.Ash.Ksef.Workers.FetchWorker
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor

  require Ash.Query

  setup do
    admin = admin_fixture()
    organization_id = admin.organization_id

    Cachex.put(:ksef, {:access_token, organization_id}, "test-access-token", expire: to_timeout(minute: 5))

    original_ksef_config = Application.fetch_env!(:firmowid, :ksef)
    original_openai_enrichment = Application.get_env(:firmowid, :openai_enrichment)

    Application.put_env(
      :firmowid,
      :ksef,
      Keyword.merge(original_ksef_config,
        base_url: "https://ksef.example",
        request_options: [plug: {Req.Test, :ksef_api}]
      )
    )

    Application.put_env(
      :firmowid,
      :openai_enrichment,
      request_options: [plug: {Req.Test, :openai_enrichment}]
    )

    stub_openai_enrichment_request()

    on_exit(fn ->
      Application.put_env(:firmowid, :ksef, original_ksef_config)
      restore_env(:openai_enrichment, original_openai_enrichment)
      Cachex.del(:ksef, {:access_token, organization_id})
    end)

    %{organization_id: organization_id, scope: ksef_scope(organization_id)}
  end

  defp restore_env(key, nil), do: Application.delete_env(:firmowid, key)
  defp restore_env(key, value), do: Application.put_env(:firmowid, key, value)

  test "imports invoices from a mocked completed export package", %{
    organization_id: organization_id,
    scope: scope
  } do
    ksef_number = "KSEF-IMPORT-#{System.unique_integer([:positive])}"
    storage_date = "2026-03-06T12:34:56Z"
    encryption_data = Encryption.generate_encryption_data()

    xml = invoice_xml(invoice_identifier: "FETCH/2026/001", total_amount: "123.45")

    {zip_binary, encrypted_package} =
      build_encrypted_package(
        [%{ksef_number: ksef_number, xml: xml, permanent_storage_date: storage_date}],
        encryption_data
      )

    part = package_part(zip_binary, encrypted_package, "https://ksef.example/downloads/package-1")

    Req.Test.stub(:ksef_api, fn conn ->
      case conn.request_path do
        "/invoices/exports/export-ref-1" ->
          Req.Test.json(conn, %{
            "status" => %{"code" => 200},
            "package" => %{"parts" => [part], "isTruncated" => false}
          })

        "/downloads/package-1" ->
          Plug.Conn.send_resp(conn, 200, encrypted_package)

        _ ->
          Plug.Conn.send_resp(conn, 404, "unexpected request: #{conn.request_path}")
      end
    end)

    assert :ok =
             perform_job(
               FetchWorker,
               poll_export_args(organization_id, encryption_data, "export-ref-1")
             )

    [invoice] = cost_invoices_by_ksef_number([ksef_number], scope)

    assert invoice.ksef_number == ksef_number
    assert invoice.invoice_identifier == "FETCH/2026/001"
    assert Decimal.equal?(invoice.total_amount, Decimal.new("-123.45"))
    assert {:ok, permanent_storage_date, 0} = DateTime.from_iso8601(storage_date)
    assert invoice.ksef_permanent_storage_date == DateTime.to_naive(permanent_storage_date)
    assert %DateTime{} = invoice.ksef_downloaded_at
    assert invoice.blob_id
  end

  test "skips already imported KSeF invoices while importing new ones from a mocked export", %{
    organization_id: organization_id,
    scope: scope
  } do
    existing_ksef_number = "KSEF-DUP-#{System.unique_integer([:positive])}"
    new_ksef_number = "KSEF-NEW-#{System.unique_integer([:positive])}"
    storage_date = "2026-03-07T08:00:00Z"
    encryption_data = Encryption.generate_encryption_data()

    insert_existing_cost_invoice!(organization_id, existing_ksef_number)

    {zip_binary, encrypted_package} =
      build_encrypted_package(
        [
          %{
            ksef_number: existing_ksef_number,
            xml: invoice_xml(invoice_identifier: "FETCH/DUPLICATE/001", total_amount: "50.00"),
            permanent_storage_date: storage_date
          },
          %{
            ksef_number: new_ksef_number,
            xml: invoice_xml(invoice_identifier: "FETCH/NEW/002", total_amount: "75.50"),
            permanent_storage_date: storage_date
          }
        ],
        encryption_data
      )

    part = package_part(zip_binary, encrypted_package, "https://ksef.example/downloads/package-2")

    Req.Test.stub(:ksef_api, fn conn ->
      case conn.request_path do
        "/invoices/exports/export-ref-2" ->
          Req.Test.json(conn, %{
            "status" => %{"code" => 200},
            "package" => %{"parts" => [part], "isTruncated" => false}
          })

        "/downloads/package-2" ->
          Plug.Conn.send_resp(conn, 200, encrypted_package)

        _ ->
          Plug.Conn.send_resp(conn, 404, "unexpected request: #{conn.request_path}")
      end
    end)

    assert :ok =
             perform_job(
               FetchWorker,
               poll_export_args(organization_id, encryption_data, "export-ref-2")
             )

    invoices = cost_invoices_by_ksef_number([existing_ksef_number, new_ksef_number], scope)

    assert Enum.count(invoices, &(&1.ksef_number == existing_ksef_number)) == 1

    imported_invoice = Enum.find(invoices, &(&1.ksef_number == new_ksef_number))
    assert imported_invoice
    assert imported_invoice.invoice_identifier == "FETCH/NEW/002"
    assert Decimal.equal?(imported_invoice.total_amount, Decimal.new("-75.50"))
  end

  defp ksef_scope(organization_id) do
    %Scope{
      actor: %SystemActor{org_id: organization_id, role: :ksef_session},
      tenant: organization_id
    }
  end

  defp poll_export_args(organization_id, encryption_data, reference_number) do
    %{
      "action" => "poll_export",
      "organization_id" => organization_id,
      "reference_number" => reference_number,
      "encryption_key" => Base.encode64(encryption_data.key),
      "encryption_iv" => Base.encode64(encryption_data.iv),
      "date_from" => "2026-03-01T00:00:00Z"
    }
  end

  defp build_encrypted_package(invoices, encryption_data) do
    metadata_json = metadata_json(invoices)

    zip_entries = [
      {~c"_metadata.json", metadata_json}
      | Enum.map(invoices, fn %{ksef_number: ksef_number, xml: xml} ->
          {String.to_charlist("#{ksef_number}.xml"), xml}
        end)
    ]

    {:ok, {_name, zip_binary}} = :zip.create(~c"ksef-export.zip", zip_entries, [:memory])

    encrypted_package =
      Encryption.encrypt_aes256_cbc(zip_binary, encryption_data.key, encryption_data.iv)

    {zip_binary, encrypted_package}
  end

  defp metadata_json(invoices) do
    invoices
    |> Enum.map(fn %{ksef_number: ksef_number, permanent_storage_date: permanent_storage_date} ->
      %{
        "ksefNumber" => ksef_number,
        "permanentStorageDate" => permanent_storage_date
      }
    end)
    |> then(&%{"invoices" => &1})
    |> Jason.encode!()
  end

  defp package_part(zip_binary, encrypted_package, url) do
    encrypted_hash = :crypto.hash(:sha256, encrypted_package)
    part_hash = :crypto.hash(:sha256, zip_binary)

    %{
      "ordinalNumber" => 1,
      "url" => url,
      "method" => "GET",
      "expirationDate" => DateTime.utc_now() |> DateTime.shift(hour: 1) |> DateTime.to_iso8601(),
      "partHash" => Base.encode64(part_hash),
      "encryptedPartHash" => Base.encode64(encrypted_hash)
    }
  end

  defp cost_invoices_by_ksef_number(ksef_numbers, scope) do
    CostInvoice
    |> Ash.Query.filter(ksef_number in ^ksef_numbers)
    |> Ash.Query.sort(ksef_number: :asc)
    |> Ash.Query.load([:blob])
    |> Ash.read!(scope: scope)
  end

  defp insert_existing_cost_invoice!(organization_id, ksef_number) do
    Ash.Seed.seed!(CostInvoice, %{
      seller: "Existing Supplier Sp. z o.o.",
      seller_display_name: "Existing Supplier",
      seller_address: "ul. Testowa 1, 00-001 Warszawa",
      sale_date: ~D[2026-03-01],
      issue_date: ~D[2026-03-01],
      due_date: ~D[2026-03-15],
      total_amount: Decimal.new("-50.00"),
      currency: "PLN",
      amount: Money.new!("PLN", Decimal.new("-50.00")),
      description: "Existing imported invoice",
      invoice_identifier: "EXISTING/#{System.unique_integer([:positive])}",
      skip_invoicing: false,
      organization_id: organization_id,
      ksef_number: ksef_number,
      ksef_permanent_storage_date: ~N[2026-03-01 08:00:00],
      ksef_downloaded_at: DateTime.utc_now()
    })
  end

  defp invoice_xml(opts) do
    invoice_identifier = Keyword.fetch!(opts, :invoice_identifier)
    total_amount = Keyword.fetch!(opts, :total_amount)

    """
    <?xml version="1.0" encoding="utf-8"?>
    <Faktura xmlns="http://crd.gov.pl/wzor/2025/06/25/13775/">
      <Podmiot1>
        <DaneIdentyfikacyjne>
          <NIP>7191575524</NIP>
          <Nazwa>Mocked Supplier</Nazwa>
        </DaneIdentyfikacyjne>
        <Adres>
          <KodKraju>PL</KodKraju>
          <AdresL1>ul. Mockowana 10, 00-100 Warszawa</AdresL1>
        </Adres>
      </Podmiot1>
      <Fa>
        <KodWaluty>PLN</KodWaluty>
        <P_1>2026-03-06</P_1>
        <P_2>#{invoice_identifier}</P_2>
        <P_15>#{total_amount}</P_15>
        <RodzajFaktury>VAT</RodzajFaktury>
        <Platnosc>
          <FormaPlatnosci>6</FormaPlatnosci>
          <TerminPlatnosci>
            <Termin>2026-03-20</Termin>
          </TerminPlatnosci>
        </Platnosc>
        <FaWiersz>
          <NrWierszaFa>1</NrWierszaFa>
          <P_7>Imported line</P_7>
          <P_8B>1</P_8B>
          <P_9A>#{total_amount}</P_9A>
        </FaWiersz>
      </Fa>
    </Faktura>
    """
  end
end
