defmodule Firmowid.Ash.Delegations.DelegationExpenseExtractorTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Firmowid.Ash.Delegations.DelegationExpense.Trip
  alias Firmowid.Ash.Delegations.DelegationExpenseExtractor
  alias Firmowid.Ash.Invoicing.Services.ReductoApiClientMock

  test "sends explicit category details schemas through the standard Extract request" do
    previous_config = Application.get_env(:firmowid, :reducto_api_client)
    previous_client = Application.get_env(:firmowid, :reducto_api_client_module)
    Application.delete_env(:firmowid, :reducto_api_client_module)

    Application.put_env(:firmowid, :reducto_api_client,
      upload: [plug: {Req.Test, __MODULE__}],
      extract: [plug: {Req.Test, __MODULE__}]
    )

    on_exit(fn ->
      restore_env(:reducto_api_client, previous_config)
      restore_env(:reducto_api_client_module, previous_client)
    end)

    path = Briefly.create!()
    File.write!(path, "expense document")

    for {category, fields} <- [
          transport: ~w(type transport_type trips),
          accommodation: ~w(type locality arrival_date departure_date description),
          other: ~w(type description)
        ] do
      Req.Test.stub(__MODULE__, fn
        %{request_path: "/upload"} = conn ->
          Req.Test.json(conn, %{file_id: "test-file"})

        %{request_path: "/extract"} = conn ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          request = Jason.decode!(body)
          schema = get_in(request, ["instructions", "schema", "properties", "details"])
          assert Enum.sort(Map.keys(schema["properties"])) == Enum.sort(fields)
          assert schema["properties"]["type"]["enum"] == [Atom.to_string(category)]
          refute Map.get(request["settings"], "deep_extract", false)

          if category == :transport do
            assert get_in(schema, ["properties", "transport_type", "enum"]) ==
                     ["railway", "airplane", "bus", "other"]

            assert schema["properties"]["trips"]["items"]["properties"]
                   |> Map.keys()
                   |> Enum.sort() ==
                     ~w(arrival_city arrival_datetime departure_city departure_datetime)
          end

          Req.Test.json(conn, %{
            result: %{
              document_number: "EXP/1",
              expense_amount: 10.5,
              details: %{type: nil, description: nil}
            }
          })
      end)

      assert {:ok, %{details: %{"_union_type" => union_type, "type" => details_type}}} =
               DelegationExpenseExtractor.extract(path, category, ~D[2026-08-10], ~D[2026-08-11])

      assert union_type == Atom.to_string(category)
      assert details_type == Atom.to_string(category)
    end
  end

  test "preserves ticket wall clocks through DST gaps, both overlap offsets and transatlantic flights" do
    configure_req_mock()

    for {departure, arrival, local_departure, local_arrival, utc_departure, utc_arrival} <- [
          {"2026-03-29T02:30:00", "2026-03-29T03:30:00", ~N[2026-03-29 02:30:00], ~N[2026-03-29 03:30:00], nil, nil},
          {"2026-10-25T02:30:00+02:00", "2026-10-25T02:30:00+01:00", ~N[2026-10-25 02:30:00], ~N[2026-10-25 02:30:00],
           ~U[2026-10-25 00:30:00Z], ~U[2026-10-25 01:30:00Z]},
          {"2026-09-10T12:00:00+02:00", "2026-09-10T11:00:00-04:00", ~N[2026-09-10 12:00:00], ~N[2026-09-10 11:00:00],
           ~U[2026-09-10 10:00:00Z], ~U[2026-09-10 15:00:00Z]},
          {"2026-09-12T00:30:00+02:00", "2026-09-12T01:30:00+02:00", ~N[2026-09-12 00:30:00], ~N[2026-09-12 01:30:00],
           ~U[2026-09-11 22:30:00Z], ~U[2026-09-11 23:30:00Z]},
          {"2026-09-10T12:00:00Z", "2026-09-10T13:00:00Z", ~N[2026-09-10 12:00:00], ~N[2026-09-10 13:00:00],
           ~U[2026-09-10 12:00:00Z], ~U[2026-09-10 13:00:00Z]}
        ] do
      stub_ticket(departure, arrival)
      assert {:ok, %{details: %{"trips" => [params]}}} = extract_ticket()
      assert params["departure_local_datetime"] == local_departure
      assert params["arrival_local_datetime"] == local_arrival
      assert params["departure_datetime"] == utc_departure
      assert params["arrival_datetime"] == utc_arrival
      assert {:ok, trip} = Ash.Type.cast_input(Trip, params)
      assert {:ok, embedded} = Ash.Type.dump_to_embedded(Trip, trip)
      assert {:ok, restored} = Ash.Type.cast_stored(Trip, embedded)
      assert restored.departure_datetime == utc_departure
      assert restored.arrival_datetime == utc_arrival
      assert Trip.local_datetime(restored, :departure) == local_departure
      assert Trip.local_datetime(restored, :arrival) == local_arrival
    end
  end

  test "reports invalid ticket timestamps without timezone guessing or silent fallback" do
    configure_req_mock()

    for value <- [
          "2026-02-30T02:30:00",
          "2026-10-25T02:30:00 Europe/Warsaw",
          "2026-10-25T02:30:00+99:00",
          "not a date",
          123
        ] do
      stub_ticket(value, "2026-10-25T03:30:00")

      capture_log(fn ->
        assert {:error, {:invalid_trip_datetime, "departure_datetime", ^value, _reason}} =
                 extract_ticket()
      end)
    end
  end

  defp configure_req_mock do
    previous_config = Application.get_env(:firmowid, :reducto_api_client)
    previous_client = Application.get_env(:firmowid, :reducto_api_client_module)
    Application.delete_env(:firmowid, :reducto_api_client_module)

    Application.put_env(:firmowid, :reducto_api_client,
      upload: [plug: {Req.Test, __MODULE__}],
      extract: [plug: {Req.Test, __MODULE__}]
    )

    on_exit(fn ->
      restore_env(:reducto_api_client, previous_config)
      restore_env(:reducto_api_client_module, previous_client)
    end)
  end

  defp stub_ticket(departure, arrival) do
    Req.Test.stub(__MODULE__, fn
      %{request_path: "/upload"} = conn ->
        Req.Test.json(conn, %{file_id: "test-ticket"})

      %{request_path: "/extract"} = conn ->
        Req.Test.json(conn, %{
          result: %{
            document_number: "TICKET/1",
            expense_amount: 100,
            details: %{
              trips: [
                %{
                  departure_city: "Warszawa",
                  arrival_city: "Nowy Jork",
                  departure_datetime: departure,
                  arrival_datetime: arrival
                }
              ]
            }
          }
        })
    end)
  end

  defp extract_ticket do
    path = Briefly.create!()
    File.write!(path, "ticket")
    DelegationExpenseExtractor.extract(path, :transport, ~D[2026-09-10], ~D[2026-09-11])
  end

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

    capture_log(fn ->
      for expense_type <- [:transport, :accommodation, :other] do
        assert {:error, :unavailable} =
                 DelegationExpenseExtractor.extract(
                   "/tmp/document.pdf",
                   expense_type,
                   ~D[2026-08-10],
                   ~D[2026-08-11]
                 )
      end
    end)
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
                  "departure_datetime" => nil,
                  "departure_local_datetime" => ~N[2026-08-10 08:15:00],
                  "arrival_city" => "Kraków",
                  "arrival_datetime" => nil,
                  "arrival_local_datetime" => ~N[2026-08-10 11:30:00]
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
