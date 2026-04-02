defmodule Firmowid.Ash.Finances.GoCardless.ApiClientTest do
  use ExUnit.Case, async: true

  alias Firmowid.Ash.Finances.GoCardless.ApiClient

  @moduletag capture_log: true

  describe "get_available_institutions_for_country/1" do
    test "returns {:ok, list} on 200" do
      Req.Test.stub(:bank_data_institutions, fn conn ->
        Req.Test.json(conn, [%{"id" => "N26", "name" => "N26 Bank"}])
      end)

      assert {:ok, [%{"id" => "N26"}]} = ApiClient.get_available_institutions_for_country("PL")
    end

    test "returns {:error, :unauthorized} on 401" do
      Req.Test.stub(:bank_data_institutions, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          401,
          Jason.encode!(%{summary: "Invalid token", detail: "expired", status_code: 401})
        )
      end)

      assert {:error, :unauthorized} = ApiClient.get_available_institutions_for_country("PL")
    end

    test "returns {:error, :rate_limited} on 429" do
      Req.Test.stub(:bank_data_institutions, fn conn ->
        Plug.Conn.send_resp(conn, 429, "")
      end)

      assert {:error, :rate_limited} = ApiClient.get_available_institutions_for_country("PL")
    end
  end

  describe "get_requisition/1" do
    test "returns {:ok, map} on 200" do
      Req.Test.stub(:bank_data_requisition, fn conn ->
        Req.Test.json(conn, %{id: "req-1", status: "LN"})
      end)

      assert {:ok, %{"id" => "req-1", "status" => "LN"}} = ApiClient.get_requisition("req-1")
    end

    test "returns {:error, :not_found} on 404" do
      Req.Test.stub(:bank_data_requisition, fn conn ->
        Plug.Conn.send_resp(conn, 404, "")
      end)

      assert {:error, :not_found} = ApiClient.get_requisition("nonexistent")
    end

    test "returns {:error, :unauthorized} on 401" do
      Req.Test.stub(:bank_data_requisition, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          401,
          Jason.encode!(%{summary: "Invalid token", detail: "expired", status_code: 401})
        )
      end)

      assert {:error, :unauthorized} = ApiClient.get_requisition("req-1")
    end
  end

  describe "get_booked_transactions_for_account/1" do
    test "returns {:ok, transactions} on 200" do
      Req.Test.stub(:bank_data_transactions, fn conn ->
        Req.Test.json(conn, %{
          transactions: %{
            booked: [%{transactionId: "1", transactionAmount: %{amount: "-10", currency: "PLN"}}],
            pending: []
          }
        })
      end)

      assert {:ok, [%{"transactionId" => "1"}]} =
               ApiClient.get_booked_transactions_for_account("acc-1")
    end

    test "returns {:error, :expired_eua} on 401 with EUA message" do
      Req.Test.stub(:bank_data_transactions, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          401,
          Jason.encode!(%{
            summary: "End User Agreement (EUA) abc123 has expired",
            detail: "EUA was valid for 90 days",
            status_code: 401
          })
        )
      end)

      assert {:error, :expired_eua} = ApiClient.get_booked_transactions_for_account("acc-1")
    end

    test "returns {:error, :unauthorized} on 401 without EUA message" do
      Req.Test.stub(:bank_data_transactions, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          401,
          Jason.encode!(%{summary: "Invalid token", detail: "Token is invalid", status_code: 401})
        )
      end)

      assert {:error, :unauthorized} = ApiClient.get_booked_transactions_for_account("acc-1")
    end

    test "returns {:error, :forbidden} on 403" do
      Req.Test.stub(:bank_data_transactions, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(403, Jason.encode!(%{summary: "Forbidden", status_code: 403}))
      end)

      assert {:error, :forbidden} = ApiClient.get_booked_transactions_for_account("acc-1")
    end

    test "returns {:error, :not_found} on 404" do
      Req.Test.stub(:bank_data_transactions, fn conn ->
        Plug.Conn.send_resp(conn, 404, "")
      end)

      assert {:error, :not_found} = ApiClient.get_booked_transactions_for_account("acc-1")
    end

    test "returns {:error, :conflict} on 409" do
      Req.Test.stub(:bank_data_transactions, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          409,
          Jason.encode!(%{summary: "Account suspended", status_code: 409})
        )
      end)

      assert {:error, :conflict} = ApiClient.get_booked_transactions_for_account("acc-1")
    end

    test "returns {:error, :rate_limited} on 429" do
      Req.Test.stub(:bank_data_transactions, fn conn ->
        Plug.Conn.send_resp(conn, 429, "")
      end)

      assert {:error, :rate_limited} = ApiClient.get_booked_transactions_for_account("acc-1")
    end

    test "returns {:error, :server_error} on 500" do
      Req.Test.stub(:bank_data_transactions, fn conn ->
        Plug.Conn.send_resp(conn, 500, "")
      end)

      assert {:error, :server_error} = ApiClient.get_booked_transactions_for_account("acc-1")
    end

    test "returns {:error, :server_error} on 503" do
      Req.Test.stub(:bank_data_transactions, fn conn ->
        Plug.Conn.send_resp(conn, 503, "")
      end)

      assert {:error, :server_error} = ApiClient.get_booked_transactions_for_account("acc-1")
    end
  end

  describe "get_institution/1" do
    test "returns {:ok, map} on 200" do
      Req.Test.stub(:bank_data_institution, fn conn ->
        Req.Test.json(conn, %{name: "N26 Bank", transaction_total_days: "90"})
      end)

      assert {:ok, %{"name" => "N26 Bank"}} = ApiClient.get_institution("N26")
    end

    test "returns {:error, :not_found} on 404" do
      Req.Test.stub(:bank_data_institution, fn conn ->
        Plug.Conn.send_resp(conn, 404, "")
      end)

      assert {:error, :not_found} = ApiClient.get_institution("NONEXISTENT")
    end
  end

  describe "get_account_status/1" do
    test "returns {:ok, map} on 200" do
      Req.Test.stub(:bank_data_account, fn conn ->
        Req.Test.json(conn, %{id: "acc-1", institution_id: "N26", status: "READY"})
      end)

      assert {:ok, %{"id" => "acc-1"}} = ApiClient.get_account_status("acc-1")
    end

    test "returns {:error, :unauthorized} on 401" do
      Req.Test.stub(:bank_data_account, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(401, Jason.encode!(%{summary: "Invalid token", status_code: 401}))
      end)

      assert {:error, :unauthorized} = ApiClient.get_account_status("acc-1")
    end
  end

  describe "get_account_details/1" do
    test "returns {:ok, account_map} extracting nested account key on 200" do
      Req.Test.stub(:bank_data_requisition, fn conn ->
        Req.Test.json(conn, %{account: %{name: "Main", iban: "PL00", currency: "PLN"}})
      end)

      assert {:ok, %{"name" => "Main", "iban" => "PL00"}} = ApiClient.get_account_details("acc-1")
    end
  end
end
