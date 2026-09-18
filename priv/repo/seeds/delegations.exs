defmodule Firmowid.Seeds.Delegations do
  @moduledoc "Seeds example business-trip delegations for Kira Voss."

  alias Firmowid.Ash.Delegations.Delegation
  alias Firmowid.Ash.Delegations.DelegationExpense
  alias Firmowid.Seeds.Helpers

  @seed_actor %{id: "00000000-0000-0000-0000-000000000000", role: :admin}
  @timezone "Europe/Warsaw"

  def seed!(%{users: %{kira: kira}, bytecraft: bytecraft}) do
    monday = next_monday()
    thursday = Date.add(monday, 3)
    friday = Date.add(monday, 4)
    sunday = Date.add(monday, 6)

    train =
      seed_delegation!(
        "Delegacja Wrocław - Kraków",
        "Kraków",
        [:railway],
        "Spotkanie projektowe w Krakowie",
        monday,
        thursday,
        "1200.00",
        kira.id,
        bytecraft.id
      )

    seed_expense!(train, bytecraft.id, :transport, "bilet-pkp-wroclaw-krakow.pdf", "110.00", %{type: "transport", transport_type: :railway, trips: [trip(monday, ~T[07:30:00], "Wrocław Główny", monday, ~T[11:00:00], "Kraków Główny")]})
    seed_expense!(train, bytecraft.id, :transport, "bilet-pkp-krakow-wroclaw.pdf", "110.00", %{type: "transport", transport_type: :railway, trips: [trip(thursday, ~T[18:30:00], "Kraków Główny", thursday, ~T[22:00:00], "Wrocław Główny")]})
    seed_expense!(train, bytecraft.id, :accommodation, "nocleg-studencka.pdf", "900.00", %{type: "accommodation", locality: "Studencka 12, Kraków", arrival_date: monday, departure_date: thursday, description: "Nocleg na 3 noce przy ul. Studenckiej"})

    flight =
      seed_delegation!(
        "Delegacja Kraków - Londyn",
        "Londyn",
        [:airplane],
        "Warsztaty z zespołem w Londynie",
        friday,
        sunday,
        "3000.00",
        kira.id,
        bytecraft.id
      )

    seed_expense!(flight, bytecraft.id, :transport, "bilet-lotniczy-londyn.pdf", "1250.00", %{type: "transport", transport_type: :airplane, trips: [trip(friday, ~T[08:00:00], "Kraków Airport", friday, ~T[09:30:00], "London Heathrow"), trip(sunday, ~T[20:00:00], "London Heathrow", sunday, ~T[23:20:00], "Kraków Airport")]})
    seed_expense!(flight, bytecraft.id, :accommodation, "nocleg-londyn.pdf", "1400.00", %{type: "accommodation", locality: "18 Borough High Street, London", arrival_date: friday, departure_date: sunday, description: "Nocleg na 2 noce w Londynie"})
    seed_expense!(flight, bytecraft.id, :other, "transfer-londyn.pdf", "85.00", %{type: "other", description: "Transfer lotnisko - hotel"})
  end

  defp seed_delegation!(
         title,
         destination,
         transport_types,
         purpose,
         start_date,
         end_date,
         expected_cost,
         user_id,
         organization_id
       ) do
    Ash.Seed.seed!(
      Delegation,
      %{
        title: title,
        destination: destination,
        transport_types: transport_types,
        purpose: purpose,
        billing_month: Date.beginning_of_month(start_date),
        start_date: start_date,
        end_date: end_date,
        expected_cost: Helpers.money!(:PLN, expected_cost),
        advance_amount: Helpers.money!(:PLN, expected_cost),
        status: :in_progress,
        user_id: user_id,
        organization_id: organization_id
      },
      tenant: organization_id
    )
  end

  defp seed_expense!(delegation, organization_id, kind, filename, amount, details) do
    Ash.Seed.seed!(DelegationExpense, %{delegation_id: delegation.id, organization_id: organization_id, kind: kind, original_filename: filename, document_number: "DEMO-#{delegation.id}", expense_amount: Helpers.money!(:PLN, amount), details: details}, tenant: organization_id)
  end

  defp trip(departure_date, departure_time, departure_city, arrival_date, arrival_time, arrival_city), do: %{departure_city: departure_city, departure_datetime: DateTime.new!(departure_date, departure_time, @timezone), arrival_city: arrival_city, arrival_datetime: DateTime.new!(arrival_date, arrival_time, @timezone)}
  defp next_monday, do: Helpers.today() |> then(&Date.add(&1, rem(8 - Date.day_of_week(&1), 7)))
end
