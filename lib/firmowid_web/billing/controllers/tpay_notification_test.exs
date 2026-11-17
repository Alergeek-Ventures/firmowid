defmodule FirmowidWeb.Billing.Controllers.TpayNotificationTest do
  @moduledoc false
  # The Tpay client reads made-up credentials from the application environment.
  use FirmowidWeb.ConnCase, async: false

  import ExUnit.CaptureLog
  import Firmowid.AccountsFixtures
  import Firmowid.BillingFixtures

  alias Firmowid.Billing
  alias Firmowid.Billing.Month
  alias Firmowid.Billing.Subscription
  alias Firmowid.Core
  alias Firmowid.Repo
  alias Firmowid.Test.Support.TpayStub

  setup {TpayStub, :put_credentials}

  describe "card tokenization" do
    test "activates the subscription awaiting the card once and refuses an unsigned notification",
         %{conn: conn} do
      org_id = admin_fixture().member.organization_id
      awaiting = awaiting_card(org_id, "TOK-1")
      TpayStub.stub()

      body = tokenization("TOK-1")

      assert conn |> notify(body, TpayStub.sign(body)) |> json_response(200) == %{
               "result" => true
             }

      active = Repo.reload!(awaiting)

      assert %{status: :active, card_tail: "1234", card_brand: "Visa", activated_at: %DateTime{}} =
               active

      assert organization(org_id).billing_plan == :przedsiebiorca

      # The first month is free: nothing is charged and the first charge waits for the next month.
      assert active.next_charge_on == Month.next()
      assert Billing.list_payments!(scope: Billing.scope(org_id)) == []
      refute_received {:tpay_request, "POST", "/transactions"}

      # Tpay sends a notification again until it gets the answer.
      assert build_conn() |> notify(body, TpayStub.sign(body)) |> json_response(200) == %{
               "result" => true
             }

      assert Repo.reload!(awaiting) == active

      other_org_id = admin_fixture().member.organization_id
      other = awaiting_card(other_org_id, "TOK-2")
      forged = tokenization("TOK-2")

      capture_log(fn ->
        assert build_conn() |> notify(forged, nil) |> response(400)
        assert build_conn() |> notify(forged, TpayStub.sign(body)) |> response(400)
      end)

      # Query parameters are not signed, so they cannot turn a signed notification into a tokenization.
      signed = transaction_form("TR-ANY", "not-a-payment")

      forged_query =
        URI.encode_query(%{
          "type" => "tokenization",
          "data[tokenizationId]" => "TOK-2",
          "data[token]" => "forged-card-token"
        })

      capture_log(fn ->
        assert build_conn()
               |> notify(signed, TpayStub.sign(signed), forged_query)
               |> response(200) == "TRUE"
      end)

      assert Repo.reload!(other).status == :awaiting_card
      assert organization(other_org_id).billing_plan != :przedsiebiorca
    end

    test "charges the first period at once when the organization has used its free month", %{
      conn: conn
    } do
      org_id = admin_fixture().member.organization_id

      org_id
      |> organization()
      |> Ash.Seed.update!(%{trial_granted_at: DateTime.utc_now()})

      awaiting = awaiting_card(org_id, "TOK-3")
      stub_paid_charges()

      body = tokenization("TOK-3")

      # The charge job is queued with the notification's commit and run after it, as in
      # production; inline mode would run it inside the notification's transaction.
      Oban.Testing.with_testing_mode(:manual, fn ->
        assert conn |> notify(body, TpayStub.sign(body)) |> json_response(200) == %{
                 "result" => true
               }
      end)

      assert %{success: 1} = Oban.drain_queue(queue: :billing_charges)

      assert %{status: :active} = Repo.reload!(awaiting)
      assert [%{kind: :period}] = Billing.list_payments!(scope: Billing.scope(org_id))

      assert_received {:tpay_request, "POST", "/transactions"}
      refute_received {:tpay_request, "POST", "/transactions"}
    end
  end

  describe "transaction notification" do
    test "records what Tpay states about the transaction only when it is the named attempt's", %{
      conn: conn
    } do
      subscription = active_subscription!(admin_fixture().member.organization_id)
      charging = period_payment!(subscription, %{status: :charging, attempts: 1})
      reference = "#{charging.id}:1"
      amount = charging.gross_amount

      TpayStub.stub(fn conn ->
        case conn.request_path do
          "/transactions/TR-OURS" ->
            Req.Test.json(conn, transaction("TR-OURS", reference, amount))

          "/transactions/TR-AMOUNT" ->
            Req.Test.json(conn, transaction("TR-AMOUNT", reference, Decimal.sub(amount, 1)))

          "/transactions/TR-OTHER" ->
            Req.Test.json(conn, transaction("TR-OTHER", "#{Ash.UUID.generate()}:1", amount))
        end
      end)

      capture_log(fn ->
        for foreign <- ["TR-AMOUNT", "TR-OTHER"] do
          body = transaction_form(foreign, reference)
          assert build_conn() |> notify(body, TpayStub.sign(body)) |> response(200) == "TRUE"
          assert %{status: :charging, tpay_transaction_id: nil} = Repo.reload!(charging)
        end
      end)

      body = transaction_form("TR-OURS", reference)
      assert conn |> notify(body, TpayStub.sign(body)) |> response(200) == "TRUE"

      assert %{status: :paid, tpay_transaction_id: "TR-OURS", paid_at: %DateTime{}} =
               Repo.reload!(charging)
    end
  end

  # Tpay accepts every card charge.
  defp stub_paid_charges do
    TpayStub.stub(fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      %{"amount" => amount, "hiddenDescription" => reference} = Jason.decode!(body)

      Req.Test.json(conn, %{
        "status" => "correct",
        "title" => "TR-FIRST",
        "amount" => amount,
        "hiddenDescription" => reference,
        "date" => %{"realization" => "2026-11-16 10:00:00"}
      })
    end)
  end

  defp notify(conn, body, signature, query \\ nil) do
    content_type =
      if String.starts_with?(body, "{"),
        do: "application/json",
        else: "application/x-www-form-urlencoded"

    conn
    |> put_req_header("content-type", content_type)
    |> then(&if signature, do: put_req_header(&1, "x-jws-signature", signature), else: &1)
    |> post(if(query, do: "/webhooks/tpay?" <> query, else: ~p"/webhooks/tpay"), body)
  end

  defp awaiting_card(org_id, tokenization_id) do
    Ash.Seed.seed!(Subscription, %{
      organization_id: org_id,
      plan: :przedsiebiorca,
      billing_period: :monthly,
      tokenization_id: tokenization_id
    })
  end

  defp tokenization(tokenization_id) do
    Jason.encode!(%{
      type: "tokenization",
      data: %{
        tokenizationId: tokenization_id,
        token: "card-token-#{tokenization_id}",
        cardBrand: "Visa",
        cardTail: "1234",
        tokenExpiryDate: "1230"
      }
    })
  end

  # Tpay's form notification states a status, which is not relied on: Tpay is asked instead.
  defp transaction_form(transaction_id, reference) do
    URI.encode_query(%{
      "id" => "12345",
      "tr_id" => transaction_id,
      "tr_date" => "2026-11-16 10:00:00",
      "tr_crc" => reference,
      "tr_amount" => "35.67",
      "tr_paid" => "35.67",
      "tr_status" => "TRUE",
      "tr_error" => "none",
      "tr_email" => "jan@example.com"
    })
  end

  defp transaction(transaction_id, reference, amount) do
    %{
      "title" => transaction_id,
      "status" => "correct",
      "amount" => Decimal.to_float(amount),
      "hiddenDescription" => reference,
      "date" => %{"realization" => "2026-11-16 10:00:00"}
    }
  end

  defp organization(org_id), do: Core.get_organization!(org_id, authorize?: false)
end
