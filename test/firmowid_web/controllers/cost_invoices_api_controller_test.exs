defmodule FirmowidWeb.CostInvoicesApiControllerTest do
  use FirmowidWeb.ConnCase
  use Oban.Testing, repo: Firmowid.Repo
  import Firmowid.AccountsFixtures

  describe "upload with authenticated user" do
    setup %{conn: conn} do
      {:ok,
       conn: put_req_header(conn, "accept", "application/json") |> log_in_api_user(user_fixture())}
    end

    test "uploads document successfully", %{conn: conn} do
      upload = %Plug.Upload{
        path: "test/support/fixtures/receipt.png",
        filename: "receipt.png",
        content_type: "image/png"
      }

      Oban.Testing.with_testing_mode(:manual, fn ->
        conn = post(conn, ~p"/api/cost-invoices", document: upload)

        response = json_response(conn, 200)
        assert response["message"] == "Document uploaded successfully"
        assert response["blob_id"]
      end)
    end

    test "returns error when document parameter is missing", %{conn: conn} do
      conn = post(conn, ~p"/api/cost-invoices", %{})
      response = json_response(conn, 400)
      assert response["errors"]["detail"] == "Missing document parameter"
    end

    test "returns error when document already exists", %{conn: conn} do
      upload = %Plug.Upload{
        path: "test/support/fixtures/receipt.png",
        filename: "receipt.png",
        content_type: "image/png"
      }

      Oban.Testing.with_testing_mode(:manual, fn ->
        post(conn, ~p"/api/cost-invoices", document: upload)

        conn = post(conn, ~p"/api/cost-invoices", document: upload)
        response = json_response(conn, 409)
        assert response["errors"]["detail"] == "Document already exists"
      end)
    end

    test "returns error when document is invalid", %{conn: conn} do
      upload = %Plug.Upload{
        path: "test/support/fixtures/invalid_file.txt",
        filename: "invalid_file.txt",
        content_type: "text/plain"
      }

      Oban.Testing.with_testing_mode(:manual, fn ->
        conn = post(conn, ~p"/api/cost-invoices", document: upload)
        response = json_response(conn, 422)
        assert response["errors"]["detail"] == "Unsupported content type"
      end)
    end
  end

  describe "upload with unauthenticated user" do
    setup %{conn: conn} do
      {:ok, conn: put_req_header(conn, "accept", "application/json")}
    end

    test "returns 401 when attempting to upload", %{conn: conn} do
      upload = %Plug.Upload{
        path: "test/support/fixtures/receipt.png",
        filename: "receipt.png",
        content_type: "image/png"
      }

      conn = post(conn, ~p"/api/cost-invoices", document: upload)

      assert json_response(conn, 401)["errors"]["detail"] == "Unauthorized"
    end
  end
end
