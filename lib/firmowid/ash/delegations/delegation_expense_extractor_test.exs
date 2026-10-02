defmodule Firmowid.Ash.Delegations.DelegationExpenseExtractorTest do
  use ExUnit.Case, async: false

  alias Firmowid.Ash.Delegations.DelegationExpenseExtractor
  alias Firmowid.Ash.Invoicing.Services.ReductoApiClientMock

  defmodule UnavailableReductoClient do
    @moduledoc false

    def extract_file(_path, _schema, _options), do: {:error, :unavailable}
  end

  test "returns the Reducto error when extraction is unavailable" do
    previous_client = Application.get_env(:firmowid, :reducto_api_client_module)
    Application.put_env(:firmowid, :reducto_api_client_module, UnavailableReductoClient)

    on_exit(fn ->
      restore_env(:reducto_api_client_module, previous_client)
    end)

    for expense_type <- [:transport, :accommodation, :other] do
      assert {:error, :unavailable} =
               DelegationExpenseExtractor.extract(
                 "/tmp/document.pdf",
                 expense_type,
                 ~D[2026-08-10],
                 ~D[2026-08-11]
               )
    end
  end

  test "uses category-specific development data through the configured Reducto client pipeline" do
    previous_reducto_config = Application.get_env(:firmowid, :reducto_api_client)

    Application.put_env(
      :firmowid,
      :reducto_api_client,
      upload: [plug: ReductoApiClientMock],
      extract: [plug: ReductoApiClientMock]
    )

    path = Briefly.create!()
    File.write!(path, "development document")

    on_exit(fn ->
      File.rm(path)
      restore_env(:reducto_api_client, previous_reducto_config)
    end)

    for {expense_type, document_number, amount, details} <- [
          {
            :transport,
            "DEV/TRN/2026/001",
            "123.45",
            %{
              "type" => "transport",
              "transport_type" => "railway",
              "trips" => [
                %{
                  "departure_city" => "Wrocław",
                  "departure_datetime" => "2026-08-10T08:15:00Z",
                  "arrival_city" => "Kraków",
                  "arrival_datetime" => "2026-08-10T11:30:00Z"
                }
              ],
              "_union_type" => "transport"
            }
          },
          {
            :accommodation,
            "DEV/NOC/2026/001",
            "289.00",
            %{
              "type" => "accommodation",
              "locality" => "Studencka 12, Kraków",
              "arrival_date" => "2026-08-10",
              "departure_date" => "2026-08-11",
              "description" => "Nocleg służbowy",
              "_union_type" => "accommodation"
            }
          },
          {
            :other,
            "DEV/INN/2026/001",
            "76.50",
            %{
              "type" => "other",
              "description" => "Polisa ubezpieczeniowa podróży służbowej",
              "_union_type" => "other"
            }
          }
        ] do
      assert {:ok,
              %{
                document_number: ^document_number,
                expense_amount: actual_amount,
                details: ^details
              }} =
               DelegationExpenseExtractor.extract(
                 path,
                 expense_type,
                 ~D[2026-08-10],
                 ~D[2026-08-11]
               )

      assert Money.equal?(actual_amount, Money.new(:PLN, Decimal.new(amount)))
    end
  end

  defp restore_env(key, nil), do: Application.delete_env(:firmowid, key)
  defp restore_env(key, value), do: Application.put_env(:firmowid, key, value)
end
