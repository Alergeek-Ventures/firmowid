defmodule Firmowid.Ash.Invoicing.Services.ReductoApiClientMock do
  @moduledoc """
  Local development response stub for the Reducto API.
  """

  import Plug.Conn

  @doc false
  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @doc false
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(%Plug.Conn{method: "POST", request_path: "/upload"} = conn, _opts) do
    json(conn, %{"file_id" => "dev-reducto-file"})
  end

  def call(%Plug.Conn{method: "POST", request_path: "/extract"} = conn, _opts) do
    json(conn, %{
      "result" => %{
        "document_number" => "DEV/2026/001",
        "expense_amount" => 123.45
      }
    })
  end

  def call(conn, _opts), do: send_resp(conn, 404, "not found")

  defp json(conn, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(body))
  end
end
