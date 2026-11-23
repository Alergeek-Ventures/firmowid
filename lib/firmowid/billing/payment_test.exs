defmodule Firmowid.Billing.PaymentTest do
  @moduledoc false
  use Firmowid.DataCase, async: true

  import Firmowid.AccountsFixtures
  import Firmowid.BillingFixtures

  alias Firmowid.Billing
  alias Firmowid.Billing.Payment
  alias Firmowid.Billing.StripeTerms
  alias Firmowid.Core.Organization
  alias Firmowid.Invoicing.SalesInvoice
  alias Firmowid.InvoicingFixtures
  alias Firmowid.LocalDate

  # The invoices are paid in the Stripe sandbox, with its prices and its test card.
  @moduletag :external

  test "records a paid Stripe invoice once and issues its advance invoice from Stripe's data" do
    seller_id = seller!()

    %{"latest_invoice" => stripe_invoice_id} =
      Ecto.UUID.generate() |> stripe_customer!() |> stripe_subscription!(:przedsiebiorca)

    assert {:ok, %{id: payment_id}} =
             Billing.record_payment(%{stripe_invoice_id: stripe_invoice_id},
               scope: Billing.scope(seller_id)
             )

    assert {:ok, %{id: ^payment_id}} =
             Billing.record_payment(%{stripe_invoice_id: stripe_invoice_id},
               scope: Billing.scope(seller_id)
             )

    invoice = issue_advance_invoice!(seller_id, payment_id)

    assert invoice.ksef_invoice_kind == :advance
    assert invoice.buyer_id == "1111111111"
    assert invoice.buyer_full_name == "Acme Sp. z o.o."
    assert invoice.buyer_address == "ul. Przykładowa 1, 00-001 Warszawa"
    assert Decimal.eq?(invoice.net_value, "29.00")
    assert Decimal.eq?(invoice.gross_value, "35.67")

    # The period Stripe charged for: a month from today, to the day before the next payment.
    first_day = LocalDate.today()
    last_day = first_day |> Date.shift(month: 1) |> Date.add(-1)

    assert [%{name: name}] = invoice.sales_invoice_items

    assert name ==
             "1 × Firmowid Przedsiębiorca (w cenie 35.67 zł / miesiąc), " <>
               "#{Calendar.strftime(first_day, "%d.%m.%Y")}–#{Calendar.strftime(last_day, "%d.%m.%Y")}"
  end

  test "a plan switch's invoice is named by Stripe's line description" do
    seller_id = seller!()

    %{"id" => subscription_id, "items" => %{"data" => [%{"id" => item_id}]}} =
      Ecto.UUID.generate() |> stripe_customer!() |> stripe_subscription!(:przedsiebiorca)

    # What the customer portal does on a switch to a higher plan: Stripe charges the difference
    # for the rest of the period at once.
    {:ok, %{"id" => firma_price}} = StripeTerms.price(:firma, :monthly)

    {:ok, %{"latest_invoice" => stripe_invoice_id}} =
      StripeTerms.request(:post, "/v1/subscriptions/#{subscription_id}", %{
        items: [%{id: item_id, price: firma_price}],
        proration_behavior: :always_invoice
      })

    assert {:ok, %{id: payment_id}} =
             Billing.record_payment(%{stripe_invoice_id: stripe_invoice_id},
               scope: Billing.scope(seller_id)
             )

    invoice = issue_advance_invoice!(seller_id, payment_id)

    {:ok, %{"amount_paid" => amount_paid}} =
      StripeTerms.request(:get, "/v1/invoices/#{stripe_invoice_id}")

    assert Decimal.eq?(invoice.gross_value, StripeTerms.pln(amount_paid))

    assert [%{name: "Pozostały czas dla Firmowid Firma po " <> _date_and_period}] =
             invoice.sales_invoice_items
  end

  defp issue_advance_invoice!(seller_id, payment_id) do
    assert [%{id: ^payment_id} = payment] =
             Payment.list!(%{}, scope: Billing.scope(seller_id), authorize?: false)

    # Manual mode keeps the queued KSeF submission from running against the API.
    Oban.Testing.with_testing_mode(:manual, fn ->
      AshOban.run_trigger(payment, :issue_invoice)
      assert %{success: 1} = Oban.drain_queue(queue: :billing)
    end)

    assert [%{id: ^payment_id} = invoice] =
             SalesInvoice.read!(
               scope: Billing.scope(seller_id),
               authorize?: false,
               load: [:net_value, :vat_value, :gross_value, :sales_invoice_items]
             )

    invoice
  end

  # The organization `config/test.exs` names as the seller, with a KSeF connection.
  defp seller! do
    seller_id = Billing.seller_organization_id()

    Ash.Seed.seed!(Organization, %{
      id: seller_id,
      name: "Firmowid Sp. z o.o.",
      display_name: "Firmowid",
      nip: unique_nip(),
      address: "ul. Testowa 2, 00-002 Warszawa",
      owner_id: user_fixture().id
    })

    InvoicingFixtures.connect_ksef!(seller_id)
    seller_id
  end
end
