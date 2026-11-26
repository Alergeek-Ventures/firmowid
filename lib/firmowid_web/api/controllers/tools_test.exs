defmodule FirmowidWeb.Api.Controllers.ToolsTest do
  use FirmowidWeb.ConnCase, async: true
  use Oban.Testing, repo: Firmowid.Repo, prefix: "oban"

  import Firmowid.AccountsFixtures

  alias Firmowid.Core
  alias Firmowid.Invoicing
  alias Firmowid.Invoicing.SalesInvoice
  alias Firmowid.Invoicing.SalesInvoice.Numbering
  alias Firmowid.InvoicingFixtures
  alias Firmowid.Ksef.Workers.SubmissionWorker
  alias Firmowid.LocalDate

  require Ash.Query

  setup %{conn: conn} do
    admin = admin_fixture()
    organization_id = admin.member.organization_id

    organization_id
    |> Core.get_organization!(actor: admin, tenant: organization_id)
    |> Ash.Seed.update!(%{address: "ul. Testowa 1, 00-001 Warszawa"})

    InvoicingFixtures.connect_ksef!(organization_id)

    %{conn: with_key(conn, admin, :accountant), admin: admin, organization_id: organization_id}
  end

  defp with_key(conn, admin, role) do
    key =
      Core.create_company_api_key!(%{name: "Sklep", role: role},
        actor: admin,
        tenant: admin.member.organization_id
      )

    conn
    |> put_req_header("authorization", "Bearer " <> key.__metadata__.plaintext_api_key)
    |> put_req_header("content-type", "application/json")
  end

  defp call(conn, tool, arguments), do: post(conn, "/api/v1/#{tool}", Jason.encode!(arguments))

  # Issuance queues the KSeF submission; it stays queued instead of reaching KSeF.
  defp issue(conn, attributes) do
    Oban.Testing.with_testing_mode(:manual, fn ->
      call(conn, :issue_sales_invoice_from_api, %{input: attributes})
    end)
  end

  defp paid_order(overrides \\ %{}) do
    Map.merge(
      %{
        external_id: "order-#{System.unique_integer([:positive])}",
        buyer_type: "individual",
        buyer_given_name: "Anna",
        buyer_surname: "Nowak",
        buyer_address: "ul. Polna 1, 00-001 Warszawa",
        buyer_email: "anna@example.com",
        items: [
          %{name: "Kubek", quantity: "2", unit: "szt.", unit_price: "49.00", vat_rate: "23"}
        ],
        paid_on: Date.to_iso8601(LocalDate.today()),
        payment_method: "card"
      },
      overrides
    )
  end

  defp invoice(%{"id" => id}, admin) do
    Invoicing.get_sales_invoice!(id, actor: admin, tenant: admin.member.organization_id)
  end

  describe "issue_sales_invoice_from_api" do
    test "issues a paid invoice for an individual buyer", %{conn: conn, admin: admin} do
      today = LocalDate.today()
      response = conn |> issue(paid_order(%{external_id: "order-1"})) |> json_response(200)

      assert %{
               "external_id" => "order-1",
               "paid_on" => paid_on,
               "amount" => %{"amount" => "120.54", "currency" => "PLN"},
               "ksef_submission_status" => "submitting"
             } = response

      assert paid_on == Date.to_iso8601(today)

      invoice = invoice(response, admin)
      assert invoice.invoice_number == Numbering.next_number([], :monthly, today, nil)
      assert invoice.buyer_type == :individual
      assert invoice.paid_on == today
      assert invoice.sale_date == today
      assert is_nil(invoice.due_date)
      refute invoice.should_send_emails

      # Paid on issue, the invoice expects its payment, dated `paid_on`, and counts as matched.
      scope = Firmowid.Scope.new!(admin, admin.member.organization_id)
      assert [%{date: ^today}] = Firmowid.Finances.list_expected_transactions!(scope: scope)

      assert %{reconciliation_status: :matched} =
               Ash.load!(invoice, [:reconciliation_status], scope: scope)
    end

    test "issues an invoice a company still has to pay", %{conn: conn, admin: admin} do
      due_date = Date.shift(LocalDate.today(), day: 14)

      response =
        conn
        |> issue(
          paid_order(%{
            buyer_type: "company",
            buyer_full_name: "Acme Sp. z o.o.",
            buyer_id: "1111111111",
            paid_on: nil,
            due_date: Date.to_iso8601(due_date),
            payment_method: "transfer",
            seller_account_number: "61109010140000071219812874",
            should_send_emails: true
          })
        )
        |> json_response(200)

      invoice = invoice(response, admin)
      assert invoice.buyer_type == :company
      assert invoice.due_date == due_date
      assert is_nil(invoice.paid_on)
      assert invoice.should_send_emails
    end

    test "returns the order's invoice instead of issuing a second one", %{
      conn: conn,
      admin: admin,
      organization_id: organization_id
    } do
      order = paid_order()

      first = conn |> issue(order) |> json_response(200)
      second = conn |> issue(order) |> json_response(200)

      assert second["id"] == first["id"]
      assert second["ksef_submission_status"] == "submitting"

      assert [_one] =
               SalesInvoice
               |> Ash.Query.filter(external_id == ^order.external_id)
               |> Ash.read!(actor: admin, tenant: organization_id)

      assert [_one] = all_enqueued(worker: SubmissionWorker)
    end

    test "numbers invoices one after another in the requested sequence", %{conn: conn} do
      year = LocalDate.today().year
      order = paid_order(%{numbering_format: "yearly", numbering_series: "SKLEP"})

      numbers =
        for _order <- 1..2 do
          response =
            issue(conn, %{order | external_id: "order-#{System.unique_integer([:positive])}"})

          json_response(response, 200)["invoice_number"]
        end

      assert numbers == ["SKLEP/1/#{year}", "SKLEP/2/#{year}"]
    end

    test "treats a lowercase country and a null numbering format like the defaults", %{
      conn: conn,
      admin: admin
    } do
      response =
        conn
        |> issue(paid_order(%{buyer_country: "pl", numbering_format: nil}))
        |> json_response(200)

      invoice = invoice(response, admin)
      assert invoice.buyer_country == "PL"
      assert invoice.invoice_type == :poland
      assert invoice.invoice_number == Numbering.next_number([], :monthly, LocalDate.today(), nil)
    end

    test "rejects an incomplete invoice with the field at fault", %{conn: conn} do
      response = conn |> issue(Map.delete(paid_order(), :buyer_address)) |> json_response(422)

      assert %{"error" => "operation_failed", "message" => "buyer_address: is required"} =
               response
    end
  end

  test "reads only the key's company's invoices", %{conn: conn} do
    %{"id" => id} = conn |> issue(paid_order()) |> json_response(200)
    assert %{"id" => ^id} = conn |> call(:get_sales_invoice, %{id: id}) |> json_response(200)

    other_admin = admin_fixture()

    other_invoice =
      InvoicingFixtures.seed_sales_invoice!(%{},
        scope: %Firmowid.Scope{actor: other_admin, tenant: other_admin.member.organization_id}
      )

    assert conn |> call(:get_sales_invoice, %{id: other_invoice.id}) |> json_response(422)
  end

  test "a company key has its role's permissions", %{conn: conn, admin: admin} do
    %{"id" => id} = conn |> issue(paid_order()) |> json_response(200)

    # The invoicing role only views invoices.
    view_only = with_key(build_conn(), admin, :invoicing)

    assert %{"id" => ^id} = view_only |> call(:get_sales_invoice, %{id: id}) |> json_response(200)
    assert %{"error" => "forbidden"} = view_only |> issue(paid_order()) |> json_response(403)
  end

  test "describes the MCP tools and the API-only one in OpenAPI", %{conn: conn} do
    %{"paths" => paths} = build_conn() |> get("/api/v1/openapi.json") |> json_response(200)

    assert %{"post" => %{"requestBody" => _body}} = paths["/issue_sales_invoice_from_api"]
    assert Map.has_key?(paths, "/list_sales_invoices")
    assert conn |> call(:no_such_tool, %{}) |> json_response(404)
  end
end
