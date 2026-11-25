defmodule FirmowidWeb.Invoicing.ApiTest do
  use FirmowidWeb.ConnCase, async: true
  use Oban.Testing, repo: Firmowid.Repo, prefix: "oban"

  import Firmowid.AccountsFixtures

  alias Firmowid.Core
  alias Firmowid.Core.ApiKey
  alias Firmowid.Invoicing
  alias Firmowid.Invoicing.SalesInvoice
  alias Firmowid.Invoicing.SalesInvoice.Numbering
  alias Firmowid.InvoicingFixtures
  alias Firmowid.Ksef.Workers.SubmissionWorker
  alias Firmowid.LocalDate

  require Ash.Query

  @json_api "application/vnd.api+json"

  setup %{conn: conn} do
    admin = admin_fixture()
    organization_id = admin.member.organization_id

    organization_id
    |> Core.get_organization!(actor: admin, tenant: organization_id)
    |> Ash.Seed.update!(%{address: "ul. Testowa 1, 00-001 Warszawa"})

    InvoicingFixtures.connect_ksef!(organization_id)

    key =
      Core.create_api_key!(%{name: "Sklep", scopes: [:sales_invoices]},
        actor: admin,
        tenant: organization_id
      )

    conn =
      conn
      |> put_req_header("authorization", "Bearer " <> key.__metadata__.plaintext_api_key)
      |> put_req_header("accept", @json_api)
      |> put_req_header("content-type", @json_api)

    %{conn: conn, admin: admin, organization_id: organization_id}
  end

  # Issuance queues the KSeF submission; it stays queued instead of reaching KSeF.
  defp issue(conn, attributes) do
    Oban.Testing.with_testing_mode(:manual, fn ->
      post(conn, "/api/v1/sales-invoices", Jason.encode!(%{data: %{attributes: attributes}}))
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

  defp invoice(response, admin) do
    %{"data" => %{"id" => id}} = response

    Invoicing.get_sales_invoice!(id, actor: admin, tenant: admin.member.organization_id)
  end

  describe "POST /api/v1/sales-invoices" do
    test "issues a paid invoice for an individual buyer", %{conn: conn, admin: admin} do
      today = LocalDate.today()
      response = conn |> issue(paid_order(%{external_id: "order-1"})) |> json_response(201)

      assert %{
               "type" => "sales_invoice",
               "attributes" => %{
                 "external_id" => "order-1",
                 "is_draft" => false,
                 "paid_on" => paid_on,
                 "gross_value" => _gross_value,
                 "ksef_submission_status" => "submitting"
               }
             } = response["data"]

      assert paid_on == Date.to_iso8601(today)

      invoice = invoice(response, admin)
      assert invoice.invoice_number == Numbering.next_number([], :monthly, today, nil)
      assert invoice.buyer_type == :individual
      assert invoice.paid_on == today
      assert invoice.sale_date == today
      assert invoice.skip_invoicing
      refute invoice.should_send_emails
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
        |> json_response(201)

      invoice = invoice(response, admin)
      assert invoice.buyer_type == :company
      assert invoice.due_date == due_date
      assert is_nil(invoice.paid_on)
      refute invoice.skip_invoicing
      assert invoice.should_send_emails
    end

    test "returns the order's invoice instead of issuing a second one", %{
      conn: conn,
      admin: admin,
      organization_id: organization_id
    } do
      order = paid_order()

      first = conn |> issue(order) |> json_response(201)
      second = conn |> issue(order) |> json_response(201)

      assert second["data"]["id"] == first["data"]["id"]

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

          json_response(response, 201)["data"]["attributes"]["invoice_number"]
        end

      assert numbers == ["SKLEP/1/#{year}", "SKLEP/2/#{year}"]
    end

    test "rejects an incomplete invoice with the field at fault", %{conn: conn} do
      response = conn |> issue(Map.delete(paid_order(), :buyer_address)) |> json_response(400)

      assert [%{"source" => %{"pointer" => "/data/attributes/buyer_address"}} | _errors] =
               response["errors"]
    end
  end

  describe "GET /api/v1/sales-invoices" do
    test "reads an invoice by its ID and by its order's ID", %{conn: conn} do
      order = paid_order()
      %{"data" => %{"id" => id}} = conn |> issue(order) |> json_response(201)

      assert %{"data" => %{"id" => ^id}} =
               conn |> get("/api/v1/sales-invoices/#{id}") |> json_response(200)

      assert %{"data" => %{"id" => ^id}} =
               conn
               |> get("/api/v1/sales-invoices/external-id/#{order.external_id}")
               |> json_response(200)
    end

    test "does not read another organization's invoice", %{conn: conn} do
      other_admin = admin_fixture()

      other_invoice =
        InvoicingFixtures.seed_sales_invoice!(%{external_id: "order-other"},
          scope: %Firmowid.Scope{actor: other_admin, tenant: other_admin.member.organization_id}
        )

      assert conn |> get("/api/v1/sales-invoices/#{other_invoice.id}") |> json_response(404)

      assert conn
             |> get("/api/v1/sales-invoices/external-id/order-other")
             |> json_response(404)
    end
  end

  describe "a key's access to sales invoices" do
    setup %{admin: admin} do
      # What signing in with a key puts in the actor's metadata.
      actor =
        admin
        |> Ash.Resource.put_metadata(:using_api_key?, true)
        |> Ash.Resource.put_metadata(:api_key, %ApiKey{scopes: [:sales_invoices]})

      %{key_actor: actor}
    end

    test "issues and reads, nothing else", %{
      key_actor: actor,
      admin: admin,
      organization_id: organization_id
    } do
      invoice =
        InvoicingFixtures.seed_sales_invoice!(%{},
          scope: %Firmowid.Scope{actor: admin, tenant: organization_id}
        )

      assert {:ok, _invoice} =
               Invoicing.get_sales_invoice(invoice.id, actor: actor, tenant: organization_id)

      assert Ash.can?({SalesInvoice, :issue_from_api}, actor, tenant: organization_id)
      refute Ash.can?({SalesInvoice, :issue}, actor, tenant: organization_id)
      refute Ash.can?({SalesInvoice, :draft}, actor, tenant: organization_id)
      refute Ash.can?({invoice, :revise}, actor, tenant: organization_id)
      refute Ash.can?({SalesInvoice, :cancel}, actor, tenant: organization_id)
    end

    test "needs the key's sales invoices scope", %{
      key_actor: actor,
      admin: admin,
      organization_id: organization_id
    } do
      actor = Ash.Resource.put_metadata(actor, :api_key, %ApiKey{scopes: []})

      invoice =
        InvoicingFixtures.seed_sales_invoice!(%{},
          scope: %Firmowid.Scope{actor: admin, tenant: organization_id}
        )

      assert {:error, _not_found} =
               Invoicing.get_sales_invoice(invoice.id, actor: actor, tenant: organization_id)

      refute Ash.can?({SalesInvoice, :issue_from_api}, actor, tenant: organization_id)
    end
  end
end
