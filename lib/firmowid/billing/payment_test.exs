defmodule Firmowid.Billing.PaymentTest do
  @moduledoc false
  # The Tpay client reads made-up credentials from the application environment.
  use Firmowid.DataCase, async: false

  import ExUnit.CaptureLog
  import Firmowid.AccountsFixtures
  import Firmowid.BillingFixtures
  import Swoosh.TestAssertions

  alias Firmowid.Billing
  alias Firmowid.Billing.Month
  alias Firmowid.Billing.Payment
  alias Firmowid.Core
  alias Firmowid.Core.Organization
  alias Firmowid.Invoicing.SalesInvoice
  alias Firmowid.InvoicingFixtures
  alias Firmowid.Scope
  alias Firmowid.Test.Support.TpayStub

  setup {TpayStub, :put_credentials}

  describe "daily charge" do
    test "charges the card and records the paid transaction" do
      subscription = active_subscription!(admin_fixture().member.organization_id)
      payment = period_payment!(subscription)
      stub_charges(:paid)

      AshOban.run_trigger(payment, :charge)

      assert %{status: :paid, attempts: 1, tpay_transaction_id: "TR-1", paid_at: %DateTime{}} =
               Repo.reload!(payment)

      assert_received {:charged, %{"amount" => 35.67, "hiddenDescription" => hidden_description}}
      assert hidden_description == "#{payment.id}:1"
    end

    test "tries a declined card again on the 4th and the 8th, then ends the subscription and returns the organization to Free" do
      org_id = admin_fixture().member.organization_id
      # A period already past its 8th day, so every attempt is due today.
      start = Date.shift(Month.current(), month: -1)

      subscription =
        active_subscription!(org_id, %{
          current_period_start: start,
          current_period_end: Date.end_of_month(start),
          next_charge_on: Month.current()
        })

      payment = period_payment!(subscription)
      stub_charges(:declined)

      AshOban.run_trigger(payment, :charge)
      assert %{status: :declined, attempts: 1, next_attempt_on: next} = Repo.reload!(payment)
      assert next == Date.add(start, 3)
      assert_received {:tpay_request, "POST", "/transactions/TR-1/cancel"}

      AshOban.run_trigger(payment, :charge)
      assert %{status: :declined, attempts: 2, next_attempt_on: next} = Repo.reload!(payment)
      assert next == Date.add(start, 7)
      assert organization(org_id).billing_plan == :przedsiebiorca

      AshOban.run_trigger(payment, :charge)
      assert %{status: :failed, attempts: 3} = Repo.reload!(payment)
      assert %{status: :ended, end_reason: :payment_failed} = Repo.reload!(subscription)
      assert organization(org_id).billing_plan == :free
    end

    test "a charge Tpay rejects counts as a declined attempt, so a permanent rejection ends the subscription" do
      org_id = admin_fixture().member.organization_id
      start = Date.shift(Month.current(), month: -1)

      subscription =
        active_subscription!(org_id, %{
          current_period_start: start,
          current_period_end: Date.end_of_month(start),
          next_charge_on: Month.current()
        })

      payment = period_payment!(subscription)
      stub_charges(:rejected)

      # Each rejection is reported: the charge job fails with Tpay's error.
      charge_rejected = fn ->
        capture_log(fn ->
          assert_raise Ash.Error.Unknown, ~r/rejected, 422/, fn ->
            AshOban.run_trigger(payment, :charge)
          end
        end)
      end

      charge_rejected.()

      assert %{status: :declined, attempts: 1, tpay_transaction_id: nil, next_attempt_on: next} =
               Repo.reload!(payment)

      assert next == Date.add(start, 3)

      charge_rejected.()
      charge_rejected.()

      assert %{status: :failed, attempts: 3} = Repo.reload!(payment)
      assert %{status: :ended, end_reason: :payment_failed} = Repo.reload!(subscription)
      assert organization(org_id).billing_plan == :free
      # A rejected charge has no transaction to cancel.
      refute_received {:tpay_request, "POST", "/transactions/" <> _cancel}
    end
  end

  describe "declined charge follow-up" do
    test "a failed cancel is reported, but the decline stays recorded and its email still goes out" do
      admin = admin_fixture()
      subscription = active_subscription!(admin.member.organization_id)
      payment = period_payment!(subscription)
      stub_charges(:declined, cancel_status: 500)
      flush_emails()

      capture_log(fn ->
        assert {:error, error} =
                 Billing.charge_payment(payment,
                   scope: Billing.scope(subscription.organization_id)
                 )

        assert Exception.message(error) =~ "500"
      end)

      assert_received {:tpay_request, "POST", "/transactions/TR-1/cancel"}
      assert %{status: :declined, attempts: 1} = Repo.reload!(payment)

      assert_email_sent(fn email ->
        email.subject =~ "nie przeszła" and email.to == [{"", to_string(admin.email)}]
      end)
    end
  end

  describe "no double charge" do
    test "a payment already charging is never sent to Tpay again" do
      subscription = active_subscription!(admin_fixture().member.organization_id)
      payment = period_payment!(subscription)
      scope = Billing.scope(subscription.organization_id)
      stub_charges(:pending)

      assert {:ok, %{status: :charging}} = Billing.charge_payment(payment, scope: scope)

      # The payment as a repeated job or a second request read it before the first claim.
      assert {:error, _stale} = Billing.charge_payment(payment, scope: scope)
      AshOban.run_trigger(payment, :charge)

      assert_received {:charged, _body}
      refute_received {:charged, _body}
      assert %{status: :charging, attempts: 1} = Repo.reload!(payment)
    end

    test "a repeated renewal opens one payment for the period" do
      org_id = admin_fixture().member.organization_id
      start = Date.shift(Month.current(), month: -1)

      subscription =
        active_subscription!(org_id, %{
          current_period_start: start,
          current_period_end: Date.end_of_month(start),
          next_charge_on: Month.current()
        })

      AshOban.run_trigger(subscription, :renew)

      # The same subscription as the first renewal read it.
      assert {:error, _stale} =
               subscription
               |> Ash.Changeset.for_update(:renew, %{},
                 scope: Billing.scope(org_id),
                 authorize?: false
               )
               |> Ash.update()

      assert [%{period_start: period_start, status: :due}] =
               Billing.list_payments!(scope: Billing.scope(org_id))

      assert period_start == Month.current()
      assert Repo.reload!(subscription).next_charge_on == Month.next()
      refute_received {:tpay_request, _method, _path}
    end
  end

  describe "upgrade" do
    setup do
      admin = admin_fixture()
      org_id = admin.member.organization_id
      subscription = active_subscription!(org_id)

      period_payment!(subscription, %{
        status: :paid,
        attempts: 1,
        paid_at: DateTime.utc_now(),
        tpay_transaction_id: "TR-0"
      })

      %{scope: Scope.new!(admin, org_id), subscription: subscription}
    end

    test "charges the price difference and switches the plan once it is paid", %{
      scope: scope,
      subscription: subscription
    } do
      stub_charges(:paid)

      assert {:ok, upgraded} = Billing.upgrade_subscription(subscription, :firma, scope: scope)

      assert upgraded.plan == :firma

      assert %Payment{kind: :upgrade, status: :paid} =
               payment = upgraded.__metadata__.upgrade_payment

      assert Decimal.eq?(payment.net_amount, "120.00")
      assert Decimal.eq?(payment.gross_amount, "147.60")
      assert_received {:charged, %{"amount" => 147.6}}
      assert organization(scope.tenant).billing_plan == :firma
    end

    test "keeps the plan when the card is declined", %{scope: scope, subscription: subscription} do
      stub_charges(:declined)

      assert {:ok, kept} = Billing.upgrade_subscription(subscription, :firma, scope: scope)

      assert kept.plan == :przedsiebiorca
      assert %Payment{kind: :upgrade, status: :failed} = kept.__metadata__.upgrade_payment
      assert %{status: :active, plan: :przedsiebiorca} = Repo.reload!(subscription)
      assert organization(scope.tenant).billing_plan == :przedsiebiorca
    end
  end

  describe "advance invoice" do
    test "a paid payment issues one advance invoice in the seller's organization, named by the payment" do
      seller_id = seller!()
      buyer_id = admin_fixture().member.organization_id

      buyer =
        buyer_id
        |> organization()
        |> Ash.Seed.update!(%{
          name: "Acme Sp. z o.o.",
          address: "ul. Przykładowa 1, 00-001 Warszawa"
        })

      paid =
        buyer_id
        |> active_subscription!()
        |> period_payment!(%{
          status: :paid,
          attempts: 1,
          paid_at: DateTime.utc_now(),
          tpay_transaction_id: "TR-1"
        })

      # Manual mode keeps the queued KSeF submission from running against the API.
      Oban.Testing.with_testing_mode(:manual, fn ->
        AshOban.run_trigger(paid, :issue_invoice)
        assert %{success: 1} = Oban.drain_queue(queue: :billing_invoices)

        # A repeated job finds the payment invoiced.
        AshOban.run_trigger(paid, :issue_invoice)
        Oban.drain_queue(queue: :billing_invoices)
      end)

      assert [invoice] =
               SalesInvoice.read!(
                 scope: Billing.scope(seller_id),
                 authorize?: false,
                 load: [:net_value, :vat_value, :gross_value, :sales_invoice_items]
               )

      assert invoice.id == paid.id
      assert invoice.ksef_invoice_kind == :advance
      assert invoice.buyer_id == buyer.nip
      assert Decimal.eq?(invoice.net_value, "29.00")
      assert Decimal.eq?(invoice.vat_value, "6.67")
      assert Decimal.eq?(invoice.gross_value, "35.67")
      assert [%{vat_rate: "23"}] = invoice.sales_invoice_items
      assert Repo.reload!(paid).invoiced_at
      assert SalesInvoice.read!(scope: Billing.scope(buyer_id), authorize?: false) == []
    end
  end

  # Tpay answers every card charge with the given outcome, or refuses it as invalid (`:rejected`);
  # a declined charge's transaction is cancelled, or the cancel fails with `:cancel_status`.
  defp stub_charges(outcome, opts \\ []) do
    cancel_status = Keyword.get(opts, :cancel_status, 200)
    test = self()

    TpayStub.stub(fn conn ->
      case {conn.method, conn.request_path} do
        {"POST", "/transactions"} when outcome == :rejected ->
          conn
          |> Plug.Conn.put_status(422)
          |> Req.Test.json(%{
            "result" => "failed",
            "errors" => [%{"errorCode" => "invalid_token"}]
          })

        {"POST", "/transactions"} ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          request = Jason.decode!(body)
          send(test, {:charged, request})
          Req.Test.json(conn, charge_answer(outcome, request))

        {"POST", "/transactions/" <> _cancel} ->
          conn |> Plug.Conn.put_status(cancel_status) |> Req.Test.json(%{"result" => "success"})
      end
    end)
  end

  # The emails the fixtures sent, so the next assertion sees only what the test provokes.
  defp flush_emails do
    receive do
      {:email, _email} -> flush_emails()
    after
      0 -> :ok
    end
  end

  defp charge_answer(outcome, %{"amount" => amount, "hiddenDescription" => reference}) do
    [_payment_id, attempt] = String.split(reference, ":")

    transaction = %{
      "title" => "TR-#{attempt}",
      "amount" => amount,
      "hiddenDescription" => reference,
      "date" => %{"realization" => "2026-11-16 10:00:00"}
    }

    case outcome do
      :paid ->
        Map.put(transaction, "status", "correct")

      :declined ->
        Map.merge(transaction, %{"status" => "pending", "payments" => %{"status" => "declined"}})

      :pending ->
        Map.put(transaction, "status", "pending")
    end
  end

  # The organization `config/test.exs` names as the seller, with a KSeF connection.
  defp seller! do
    seller_id = Application.fetch_env!(:firmowid, :billing)[:seller_organization_id]

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

  defp organization(org_id), do: Core.get_organization!(org_id, authorize?: false)
end
