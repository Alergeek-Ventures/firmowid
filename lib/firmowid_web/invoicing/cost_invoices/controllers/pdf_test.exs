defmodule FirmowidWeb.Invoicing.CostInvoices.Controllers.PdfTest do
  @moduledoc false
  use FirmowidWeb.ConnCase, async: false

  import ExUnit.CaptureLog
  import Firmowid.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Firmowid.Blobs
  alias Firmowid.Invoicing.CostInvoice
  alias Firmowid.Scope
  alias FirmowidWeb.Invoicing.Utilities.Navigation

  # Gotenberg is not available in CI, so rendering is stubbed with a fixed PDF body.
  setup do
    config = Application.fetch_env!(:firmowid, :gotenberg)
    Application.put_env(:firmowid, :gotenberg, Keyword.put(config, :plug, {Req.Test, :gotenberg}))
    on_exit(fn -> Application.put_env(:firmowid, :gotenberg, config) end)

    Req.Test.stub(:gotenberg, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      marker = Enum.join(Regex.run(~r/test-\d+/, body) || [])
      Plug.Conn.send_resp(conn, 200, "%PDF-1.4 #{marker}")
    end)
  end

  test "opens one KSeF PDF inline and downloads its whole correction tree from any member", %{
    conn: conn
  } do
    user = admin_fixture()
    original = invoice(user)
    first = invoice(user, original_invoice_ksef_number: original.ksef_number)
    second = invoice(user, original_invoice_ksef_number: first.ksef_number)
    sibling = invoice(user, original_invoice_ksef_number: original.ksef_number)
    _unrelated = invoice(user)
    other = admin_fixture()
    _foreign = invoice(other, original_invoice_ksef_number: original.ksef_number)
    conn = log_in_user(conn, user)

    preview = get(conn, Navigation.cost_invoice_pdf_preview_path(first))
    assert response(preview, 200) =~ "%PDF-"
    assert get_resp_header(preview, "content-type") == ["application/pdf"]
    assert ["inline;" <> _] = get_resp_header(preview, "content-disposition")

    for selected <- [original, second] do
      archive =
        get(
          conn,
          Navigation.pdf_download_path(Navigation.cost_invoice_archive_path(selected), false)
        )

      assert get_resp_header(archive, "content-type") == ["application/zip"]
      assert {:ok, entries} = :zip.extract(response(archive, 200), [:memory])

      assert length(entries) == 4

      for document <- [original, first, second, sibling] do
        expected_name = "#{document.issue_date}_#{document.invoice_identifier}_#{document.id}.pdf"

        assert {String.to_charlist(expected_name), "%PDF-1.4 #{document.invoice_identifier}"} in entries
      end
    end

    {:ok, view, _} = live(conn, ~p"/kosztowe/#{original.id}")

    assert has_element?(
             view,
             "a[href='#{Navigation.cost_invoice_pdf_preview_path(original)}'][target='_blank'].cursor-pointer"
           )

    assert has_element?(
             view,
             "button[data-download-url^='#{Navigation.cost_invoice_archive_path(original)}']"
           )

    assert has_element?(view, "button", "Pobierz faktury (ZIP)")

    {:ok, list, _} = live(conn, ~p"/fakturowanie?filtr=faktury&podfiltr=zakupowe")
    render_async(list)

    refute has_element?(list, "a[href='#{Navigation.cost_invoice_pdf_preview_path(original)}']")
    assert has_element?(list, "a[data-phx-link='redirect'][href^='/kosztowe/#{original.id}']")
  end

  test "without corrections ZIP has one PDF and legacy downloads stay PDF", %{conn: conn} do
    user = admin_fixture()
    invoice = invoice(user)
    conn = log_in_user(conn, user)
    archive = get(conn, Navigation.cost_invoice_archive_path(invoice))

    assert {:ok, [{name, <<"%PDF-", _::binary>>}]} =
             :zip.extract(response(archive, 200), [:memory])

    assert to_string(name) ==
             "#{invoice.issue_date}_#{invoice.invoice_identifier}_#{invoice.id}.pdf"

    pdf = get(conn, Navigation.cost_invoice_pdf_path(invoice))
    assert response(pdf, 200) =~ "%PDF-"
    assert ["attachment;" <> _] = get_resp_header(pdf, "content-disposition")
  end

  test "rejects foreign and unknown IDs and does not use another tenant's matching original", %{
    conn: conn
  } do
    user = admin_fixture()
    other = admin_fixture()
    foreign = invoice(other)
    orphan = invoice(user, original_invoice_ksef_number: foreign.ksef_number)
    conn = log_in_user(conn, user)

    for id <- [foreign.id, Ash.UUID.generate()],
        path <- [
          &Navigation.cost_invoice_archive_path/1,
          &Navigation.cost_invoice_pdf_preview_path/1
        ] do
      assert conn |> get(path.(id)) |> response(404)
    end

    assert conn |> get(Navigation.cost_invoice_archive_path(orphan)) |> response(422)
  end

  test "failed descendant generation returns an error instead of an incomplete ZIP", %{conn: conn} do
    user = admin_fixture()
    original = invoice(user)

    _broken =
      invoice(user, original_invoice_ksef_number: original.ksef_number, xml: "invalid XML")

    capture_log(fn ->
      result = conn |> log_in_user(user) |> get(Navigation.cost_invoice_archive_path(original))
      assert response(result, 500) == "PDF generation failed"
      refute get_resp_header(result, "content-type") == ["application/zip"]
    end)
  end

  test "archive filenames are flat and unique even for duplicate unsafe invoice numbers", %{
    conn: conn
  } do
    user = admin_fixture()
    original = invoice(user, invoice_identifier: "../same\\name")

    correction =
      invoice(user,
        invoice_identifier: original.invoice_identifier,
        original_invoice_ksef_number: original.ksef_number
      )

    archive = conn |> log_in_user(user) |> get(Navigation.cost_invoice_archive_path(correction))
    assert {:ok, entries} = :zip.extract(response(archive, 200), [:memory])
    assert length(entries) == 2
    names = Enum.map(entries, fn {name, _} -> to_string(name) end)
    assert length(Enum.uniq(names)) == 2
    assert Enum.all?(names, &(not String.contains?(&1, ["/", "\\", ".."])))
    assert [disposition] = get_resp_header(archive, "content-disposition")
    assert disposition =~ original.id
  end

  test "denies an employee access to invoices in their own company", %{conn: conn} do
    admin = admin_fixture()
    employee = user_fixture(%{role: :employee, organization_id: admin.member.organization_id})
    document = invoice(admin)
    conn = log_in_user(conn, employee)

    for path <- [
          &Navigation.cost_invoice_archive_path/1,
          &Navigation.cost_invoice_pdf_preview_path/1
        ] do
      assert conn |> get(path.(document)) |> response(404)
    end
  end

  test "missing source PDF returns an error instead of an empty archive", %{conn: conn} do
    user = admin_fixture()
    document = invoice(user, ksef_number: nil, blob_id: nil)

    capture_log(fn ->
      result = conn |> log_in_user(user) |> get(Navigation.cost_invoice_archive_path(document))
      assert response(result, 500) == "PDF generation failed"
    end)
  end

  test "rejects a cycle instead of looping", %{conn: conn} do
    user = admin_fixture()
    number = "cycle-#{System.unique_integer([:positive])}"
    invoice = invoice(user, ksef_number: number, original_invoice_ksef_number: number)

    assert conn
           |> log_in_user(user)
           |> get(Navigation.cost_invoice_archive_path(invoice))
           |> response(422)
  end

  test "rejects a two-invoice cycle", %{conn: conn} do
    user = admin_fixture()
    first = invoice(user, ksef_number: "loop-a", original_invoice_ksef_number: "loop-b")
    _second = invoice(user, ksef_number: "loop-b", original_invoice_ksef_number: "loop-a")

    assert conn
           |> log_in_user(user)
           |> get(Navigation.cost_invoice_archive_path(first))
           |> response(422)
  end

  test "anonymous downloads require sign in", %{conn: conn} do
    assert conn
           |> get(Navigation.cost_invoice_archive_path(Ash.UUID.generate()))
           |> redirected_to()
  end

  defp invoice(user, overrides \\ []) do
    scope = %Scope{actor: user, tenant: user.member.organization_id}
    number = "test-#{System.unique_integer([:positive])}"

    xml =
      Keyword.get(overrides, :xml, """
      <Faktura xmlns="http://crd.gov.pl/wzor/2025/06/25/13775/">
        <Podmiot1><DaneIdentyfikacyjne><NIP>1234567890</NIP><Nazwa>Acme</Nazwa></DaneIdentyfikacyjne></Podmiot1>
        <Podmiot2><DaneIdentyfikacyjne><NIP>0987654321</NIP><Nazwa>Example</Nazwa></DaneIdentyfikacyjne></Podmiot2>
        <Fa><KodWaluty>PLN</KodWaluty><P_1>2026-01-10</P_1><P_2>#{number}</P_2><P_15>100.00</P_15><RodzajFaktury>VAT</RodzajFaktury></Fa>
      </Faktura>
      """)

    path = Briefly.create!(extname: ".xml")
    File.write!(path, xml)
    {:ok, blob} = Blobs.create_blob(path, "application/xml", "invoice.xml", scope: scope)

    Ash.Seed.seed!(
      CostInvoice,
      Map.merge(
        %{
          seller: "Acme",
          seller_display_name: "Acme",
          seller_nip: "1234567890",
          invoice_identifier: number,
          description: "Sample invoice",
          ksef_number: number,
          blob_id: blob.id,
          issue_date: Date.utc_today(),
          sale_date: Date.utc_today(),
          amount: Money.new!(:PLN, -100),
          organization_id: user.member.organization_id
        },
        overrides |> Keyword.delete(:xml) |> Map.new()
      )
    )
  end
end
