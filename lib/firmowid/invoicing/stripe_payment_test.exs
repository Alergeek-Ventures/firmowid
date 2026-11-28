defmodule Firmowid.Invoicing.StripePaymentTest do
  @moduledoc false
  use Firmowid.DataCase, async: true

  import ExUnit.CaptureLog
  import Firmowid.AccountsFixtures
  import Firmowid.BillingFixtures

  alias Ash.Error.Forbidden
  alias Firmowid.Billing.StripeTerms
  alias Firmowid.Core
  alias Firmowid.Invoicing
  alias Firmowid.Invoicing.SalesInvoice
  alias Firmowid.Invoicing.StripeConnection
  alias Firmowid.Invoicing.StripePayment
  alias Firmowid.InvoicingFixtures
  alias Firmowid.Scope
  alias Firmowid.SystemActor

  describe "a payment in the Stripe sandbox" do
    # The payments are made in the Stripe sandbox with its test card, and the company connects
    # with the sandbox key itself: a restricted key cannot be made through the API.
    @describetag :external

    test "of a Stripe invoice is invoiced once, to the company with the tax ID, with Stripe's net and rate" do
      admin = company!(invoice_consumers: true)
      customer_id = stripe_customer!(admin.tenant)

      payment_intent_id = paid_stripe_invoice!(customer_id)

      # Stripe reports the payment again; it stays one payment with one invoice.
      record!(admin, payment_intent_id, "123.00")
      record!(admin, payment_intent_id, "123.00")

      assert [%{id: payment_id, status: :invoiced}] =
               Invoicing.list_stripe_payments!(scope: admin).results

      assert [invoice] =
               SalesInvoice.read!(
                 scope: admin,
                 load: [:net_value, :gross_value, :sales_invoice_items]
               )

      assert invoice.id == payment_id
      assert invoice.buyer_type == :company
      assert invoice.buyer_id == "1111111111"
      assert invoice.buyer_full_name == "Acme Sp. z o.o."
      assert invoice.buyer_address == "ul. Przykładowa 1, 00-001 Warszawa"
      assert invoice.payment_method == :card
      assert Decimal.eq?(invoice.net_value, "100.00")
      assert Decimal.eq?(invoice.gross_value, "123.00")
      assert [%{name: "Konsultacja", vat_rate: "23"} = item] = invoice.sales_invoice_items
      assert Decimal.eq?(item.unit_price, "100")
    end

    test "of a Stripe invoice is not invoiced when the invoice would show another amount" do
      admin = company!(invoice_consumers: true)
      payment_intent_id = admin.tenant |> stripe_customer!() |> paid_stripe_invoice!()

      # Stripe took 123.00 zł; an invoice of 123.00 zł for a payment of 123.01 zł is rolled back.
      assert capture_log(fn -> record!(admin, payment_intent_id, "123.01") end) =~
               "the invoice adds up to 123.00, Stripe took 123.01"

      assert [%{status: :pending}] = Invoicing.list_stripe_payments!(scope: admin).results
      assert [] = SalesInvoice.read!(scope: admin)
    end

    test "Stripe charged no tax on gets no invoice for a VAT payer" do
      admin = company!(invoice_consumers: true)

      record!(admin, untaxed_payment_intent!(), "123.00")

      assert [%{status: :untaxed}] = Invoicing.list_stripe_payments!(scope: admin).results
      assert [] = SalesInvoice.read!(scope: admin)
    end

    test "of a Checkout with untaxed shipping gets no invoice for a VAT payer" do
      admin = company!(invoice_consumers: true)

      # A Checkout paid in the sandbox once by hand (Checkout cannot be paid through the API):
      # 2 × "Kurs online" with VAT 8% included and 15.99 zł shipping Stripe charged no tax on.
      record!(admin, "pi_3UgYREGfxhcx7v9J0xl6HxC4", "123.99")

      assert [%{status: :untaxed}] = Invoicing.list_stripe_payments!(scope: admin).results
      assert [] = SalesInvoice.read!(scope: admin)
    end

    test "of a buyer without a tax ID is skipped when the company does not invoice private persons" do
      admin = company!(invoice_consumers: false)

      record!(admin, untaxed_payment_intent!(), "123.00")

      assert [%{status: :skipped}] = Invoicing.list_stripe_payments!(scope: admin).results
      assert [] = SalesInvoice.read!(scope: admin)
    end
  end

  describe "a refund in the Stripe sandbox" do
    @describetag :external

    test "of the whole payment corrects its invoice to zero" do
      admin = company!(invoice_consumers: true)
      payment_intent_id = admin.tenant |> stripe_customer!() |> paid_stripe_invoice!()
      record!(admin, payment_intent_id, "123.00")
      in_ksef!(admin)

      {:ok, refund} =
        StripeTerms.request(:post, "/v1/refunds", %{payment_intent: payment_intent_id})

      record_refund!(admin, refund)

      assert [%{status: :corrected, sales_invoice: %SalesInvoice{} = correction}] =
               Invoicing.list_stripe_refunds!(scope: admin).results

      correction =
        Ash.load!(correction, [:sales_invoice_items, :rounded_gross_value], scope: admin)

      assert correction.ksef_invoice_kind == :kor
      assert correction.correction_reason == "Anulowanie faktury"
      assert Decimal.eq?(correction.rounded_gross_value, 0)
      assert [%{name: "Konsultacja", quantity: quantity}] = correction.sales_invoice_items
      assert Decimal.eq?(quantity, 0)
    end

    test "with a credit note lowers the lines the note credits" do
      admin = company!(invoice_consumers: true)

      stripe_invoice_id =
        admin.tenant
        |> stripe_customer!()
        |> stripe_invoice!([
          %{description: "Szkolenie", quantity: 2, unit_amount: 5_000},
          %{description: "Materiały", quantity: 1, unit_amount: 3_000}
        ])

      payment_intent_id = pay!(stripe_invoice_id)
      record!(admin, payment_intent_id, "159.90")
      in_ksef!(admin)

      # One of the two trainings goes back: 50.00 zł and its 23% VAT.
      {:ok, %{"data" => lines}} =
        StripeTerms.request(:get, "/v1/invoices/#{stripe_invoice_id}/lines")

      training = Enum.find(lines, &(&1["description"] == "Szkolenie"))

      {:ok, %{"refunds" => [%{"refund" => refund_id}]}} =
        StripeTerms.request(:post, "/v1/credit_notes", %{
          invoice: stripe_invoice_id,
          lines: [%{type: "invoice_line_item", invoice_line_item: training["id"], quantity: 1}],
          refund_amount: 6_150
        })

      {:ok, refund} = StripeTerms.request(:get, "/v1/refunds/#{refund_id}")
      record_refund!(admin, refund)

      assert [%{status: :corrected, sales_invoice: %SalesInvoice{} = correction}] =
               Invoicing.list_stripe_refunds!(scope: admin).results

      correction =
        Ash.load!(correction, [:sales_invoice_items, :rounded_gross_value], scope: admin)

      assert Decimal.eq?(correction.rounded_gross_value, "98.40")

      assert %{
               "Szkolenie" => {training_quantity, training_price},
               "Materiały" => {materials_quantity, _price}
             } =
               Map.new(correction.sales_invoice_items, &{&1.name, {&1.quantity, &1.unit_price}})

      assert Decimal.eq?(training_quantity, 1)
      assert Decimal.eq?(training_price, 50)
      assert Decimal.eq?(materials_quantity, 1)
    end

    test "of a part of a payment without a credit note is left to the company" do
      admin = company!(invoice_consumers: true)
      payment_intent_id = admin.tenant |> stripe_customer!() |> paid_stripe_invoice!()
      record!(admin, payment_intent_id, "123.00")
      in_ksef!(admin)

      {:ok, refund} =
        StripeTerms.request(:post, "/v1/refunds", %{
          payment_intent: payment_intent_id,
          amount: 1_000
        })

      record_refund!(admin, refund)

      assert [%{status: :manual, manual_reason: :no_credit_note, sales_invoice: nil}] =
               Invoicing.list_stripe_refunds!(scope: admin).results
    end
  end

  describe "the Stripe connection and its payments" do
    setup do
      admin = admin_fixture()
      organization_id = admin.member.organization_id
      InvoicingFixtures.connect_ksef!(organization_id)

      %{admin: Scope.new!(admin, organization_id), organization_id: organization_id}
    end

    test "only an admin connects Stripe", %{organization_id: organization_id} do
      employee = Scope.new!(user_in_org_fixture(organization_id), organization_id)

      assert {:error, %Forbidden{}} =
               Invoicing.connect_stripe("rk_test_123", scope: employee)
    end

    test "hide the key from the admin and the payments from other companies", %{
      admin: admin,
      organization_id: organization_id
    } do
      Ash.Seed.seed!(
        StripeConnection,
        %{
          organization_id: organization_id,
          api_key: "rk_test_123",
          events_since: DateTime.utc_now()
        },
        tenant: organization_id
      )

      Ash.Seed.seed!(
        StripePayment,
        %{
          organization_id: organization_id,
          payment_intent_id: "pi_123",
          paid_at: DateTime.utc_now(),
          amount: Decimal.new("123.00"),
          currency: "PLN"
        },
        tenant: organization_id
      )

      assert %{api_key: %Ash.ForbiddenField{}} = Invoicing.get_stripe_connection!(scope: admin)

      assert %{results: [%{payment_intent_id: "pi_123"}]} =
               Invoicing.list_stripe_payments!(scope: admin)

      employee = Scope.new!(user_in_org_fixture(organization_id), organization_id)
      assert %{results: []} = Invoicing.list_stripe_payments!(scope: employee)

      other_admin = admin_fixture()
      other = Scope.new!(other_admin, other_admin.member.organization_id)
      assert %{results: []} = Invoicing.list_stripe_payments!(scope: other)
      assert nil == Invoicing.get_stripe_connection!(scope: other)
    end
  end

  # A VAT payer connected to KSeF and to the Stripe sandbox, as its admin sees it.
  defp company!(invoice_consumers: invoice_consumers) do
    admin = admin_fixture()
    organization_id = admin.member.organization_id
    InvoicingFixtures.connect_ksef!(organization_id)

    organization_id
    |> Core.get_organization!(authorize?: false)
    |> Ash.Seed.update!(%{address: "ul. Testowa 2, 00-002 Warszawa"})

    Ash.Seed.seed!(
      StripeConnection,
      %{
        organization_id: organization_id,
        api_key: Application.fetch_env!(:stripity_stripe, :api_key),
        invoice_consumers: invoice_consumers,
        events_since: DateTime.utc_now()
      },
      tenant: organization_id
    )

    Scope.new!(admin, organization_id)
  end

  # Records the refund as the check of Stripe's events does; the queued KSeF submission of the
  # correction does not run.
  defp record_refund!(%Scope{tenant: organization_id}, refund) do
    scope =
      Scope.new!(%SystemActor{org_id: organization_id, role: :stripe_invoicing}, organization_id)

    Oban.Testing.with_testing_mode(:manual, fn ->
      {:ok, _refund} =
        Invoicing.record_stripe_refund(
          %{
            refund_id: refund["id"],
            payment_intent_id: refund["payment_intent"],
            refunded_at: DateTime.from_unix!(refund["created"]),
            amount: StripeTerms.pln(refund["amount"]),
            currency: "PLN"
          },
          scope: scope
        )

      Oban.drain_queue(queue: :invoicing)
    end)
  end

  # KSeF accepts the company's only invoice, so it can be corrected.
  defp in_ksef!(admin) do
    [invoice] = SalesInvoice.read!(scope: admin)
    Ash.Seed.update!(invoice, %{ksef_number: "1111111111-20261128-0123456789AB-CD"})
  end

  # Records the payment as the check of Stripe's events does. Manual mode keeps the queued KSeF
  # submission of the issued invoice from running against the API.
  defp record!(%Scope{tenant: organization_id}, payment_intent_id, amount) do
    scope =
      Scope.new!(%SystemActor{org_id: organization_id, role: :stripe_invoicing}, organization_id)

    Oban.Testing.with_testing_mode(:manual, fn ->
      {:ok, _payment} =
        Invoicing.record_stripe_payment(
          %{
            payment_intent_id: payment_intent_id,
            paid_at: DateTime.utc_now(),
            amount: amount,
            currency: "PLN"
          },
          scope: scope
        )

      Oban.drain_queue(queue: :invoicing)
    end)
  end

  # Pays a Stripe invoice of one 100.00 zł line with 23% VAT added and returns its payment intent.
  defp paid_stripe_invoice!(customer_id) do
    customer_id
    |> stripe_invoice!([%{description: "Konsultacja", quantity: 1, unit_amount: 10_000}])
    |> pay!()
  end

  # A Stripe invoice of the lines, each with 23% VAT added.
  defp stripe_invoice!(customer_id, lines) do
    {:ok, %{"id" => stripe_invoice_id}} =
      StripeTerms.request(:post, "/v1/invoices", %{
        customer: customer_id,
        currency: "pln",
        auto_advance: false
      })

    for line <- lines do
      {:ok, _item} =
        StripeTerms.request(:post, "/v1/invoiceitems", %{
          customer: customer_id,
          invoice: stripe_invoice_id,
          quantity: line.quantity,
          unit_amount_decimal: Integer.to_string(line.unit_amount),
          currency: "pln",
          description: line.description,
          tax_rates: [vat_23_exclusive!()]
        })
    end

    stripe_invoice_id
  end

  # Pays the Stripe invoice with the customer's test card and returns its payment intent.
  defp pay!(stripe_invoice_id) do
    {:ok, %{"status" => "paid"}} =
      StripeTerms.request(:post, "/v1/invoices/#{stripe_invoice_id}/pay")

    {:ok, %{"data" => [%{"payment" => %{"payment_intent" => payment_intent_id}}]}} =
      StripeTerms.request(:get, "/v1/invoice_payments", %{invoice: stripe_invoice_id})

    payment_intent_id
  end

  # A card payment without an invoice or a Checkout, so without tax, and without a buyer's tax ID.
  defp untaxed_payment_intent! do
    {:ok, %{"id" => id, "status" => "succeeded"}} =
      StripeTerms.request(:post, "/v1/payment_intents", %{
        amount: 12_300,
        currency: "pln",
        payment_method: "pm_card_visa",
        payment_method_types: ["card"],
        confirm: true
      })

    id
  end

  # Stripe keeps tax rates (they can only be archived), so the tests share one.
  defp vat_23_exclusive! do
    {:ok, %{"data" => rates}} =
      StripeTerms.request(:get, "/v1/tax_rates", %{active: true, limit: 100})

    case Enum.find(
           rates,
           &(&1["display_name"] == "VAT" and &1["percentage"] == 23 and not &1["inclusive"])
         ) do
      %{"id" => id} ->
        id

      nil ->
        {:ok, %{"id" => id}} =
          StripeTerms.request(:post, "/v1/tax_rates", %{
            display_name: "VAT",
            percentage: 23,
            inclusive: false,
            country: "PL"
          })

        id
    end
  end
end
