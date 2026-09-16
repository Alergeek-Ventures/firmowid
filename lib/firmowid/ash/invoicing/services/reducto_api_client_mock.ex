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
    {:ok, body, conn} = read_body(conn)
    %{"instructions" => %{"system_prompt" => system_prompt}} = Jason.decode!(body)

    json(conn, %{"result" => extraction_result(system_prompt)})
  end

  def call(conn, _opts), do: send_resp(conn, 404, "not found")

  defp json(conn, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(body))
  end

  defp extraction_result(system_prompt) do
    {start_date, end_date} = delegation_dates(system_prompt)

    cond do
      String.contains?(system_prompt, "Expense category: transport.") ->
        %{
          "document_number" => "DEV/TRN/2026/001",
          "expense_amount" => 123.45,
          "details" => %{
            "type" => "transport",
            "transport_type" => "railway",
            "trips" => [
              %{
                "departure_city" => "Wrocław",
                "departure_datetime" => "#{start_date}T08:15:00Z",
                "arrival_city" => "Kraków",
                "arrival_datetime" => "#{start_date}T11:30:00Z"
              }
            ]
          }
        }

      String.contains?(system_prompt, "Expense category: accommodation.") ->
        %{
          "document_number" => "DEV/NOC/2026/001",
          "expense_amount" => 289.00,
          "details" => %{
            "type" => "accommodation",
            "locality" => "Studencka 12, Kraków",
            "arrival_date" => start_date,
            "departure_date" => end_date,
            "description" => "Nocleg służbowy"
          }
        }

      String.contains?(system_prompt, "Expense category: other.") ->
        %{
          "document_number" => "DEV/INN/2026/001",
          "expense_amount" => 76.50,
          "details" => %{
            "type" => "other",
            "description" => "Polisa ubezpieczeniowa podróży służbowej"
          }
        }

      true ->
        %{
          "document_number" => "DEV/2026/001",
          "expense_amount" => 123.45
        }
    end
  end

  defp delegation_dates(system_prompt) do
    case Regex.run(
           ~r/between (\d{4}-\d{2}-\d{2}) and (\d{4}-\d{2}-\d{2}), inclusive/,
           system_prompt
         ) do
      [_, start_date, end_date] -> {start_date, end_date}
      nil -> {"2026-09-14", "2026-09-15"}
    end
  end
end
