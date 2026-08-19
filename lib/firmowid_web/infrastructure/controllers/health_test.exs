defmodule FirmowidWeb.Infrastructure.Controllers.HealthTest do
  use FirmowidWeb.ConnCase, async: true

  describe "GET /health" do
    test "returns healthy status when all checks pass", %{conn: conn} do
      conn = get(conn, ~p"/health")

      assert json = json_response(conn, 200)
      assert json["status"] == "healthy"
      assert json["timestamp"]
      assert json["checks"]["database"]["status"] == "ok"
      assert json["checks"]["oban"]["status"] == "ok"
    end

    test "returns all check details in response", %{conn: conn} do
      conn = get(conn, ~p"/health")

      json = json_response(conn, 200)

      assert json["checks"]["database"]["message"] == "Database connection successful"
      assert json["checks"]["oban"]["message"] == "Oban is running"
    end

    test "exposes only stable status and message fields for public checks", %{conn: conn} do
      conn = get(conn, ~p"/health")

      json = json_response(conn, 200)

      assert Enum.all?(json["checks"], fn {_check_name, check} ->
               check |> Map.keys() |> Enum.sort() == ["message", "status"]
             end)
    end

    test "includes ISO 8601 timestamp", %{conn: conn} do
      conn = get(conn, ~p"/health")

      json = json_response(conn, 200)

      # Verify timestamp is valid ISO 8601
      assert {:ok, _datetime, _offset} = DateTime.from_iso8601(json["timestamp"])
    end
  end
end
