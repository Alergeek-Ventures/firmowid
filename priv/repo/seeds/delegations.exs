defmodule Firmowid.Seeds.Delegations do
  @moduledoc "Seeds example business-trip delegations for Kira Voss."

  alias Firmowid.Ash.Delegations.Delegation
  alias Firmowid.Ash.Delegations.DelegationExpenseAccommodation
  alias Firmowid.Ash.Delegations.DelegationExpenseOther
  alias Firmowid.Ash.Delegations.DelegationExpenseTransport
  alias Firmowid.Ash.Delegations.DelegationTrip
  alias Firmowid.Seeds.Helpers

  require Ash.Query

  @seed_actor %{id: "00000000-0000-0000-0000-000000000000", role: :admin}
  @timezone "Europe/Warsaw"

  def seed!(%{users: %{kira: kira}, bytecraft: bytecraft}) do
    monday = next_monday()
    thursday = Date.add(monday, 3)
    friday = Date.add(monday, 4)
    sunday = Date.add(monday, 6)

    train_delegation =
      seed_delegation!(
        %{
          title: "Delegacja Wrocław - Kraków",
          purpose: "Spotkanie projektowe w Krakowie",
          start_date: monday,
          end_date: thursday,
          advance_payment_amount: Helpers.money!(:PLN, "1200.00")
        },
        kira.id,
        bytecraft.id
      )

    train_expense =
      seed_transport_expense!(
        train_delegation.id,
        bytecraft.id,
        "PKP Intercity Wrocław - Kraków - Wrocław",
        "bilet-pkp-krakow.pdf",
        Helpers.money!(:PLN, "220.00")
      )

    seed_trip!(
      train_expense.id,
      bytecraft.id,
      "Wrocław Główny",
      local_datetime!(monday, ~T[07:30:00]),
      "Kraków Główny",
      local_datetime!(monday, ~T[11:00:00])
    )

    seed_trip!(
      train_expense.id,
      bytecraft.id,
      "Kraków Główny",
      local_datetime!(thursday, ~T[18:30:00]),
      "Wrocław Główny",
      local_datetime!(thursday, ~T[22:00:00])
    )

    seed_accommodation_expense!(
      train_delegation.id,
      bytecraft.id,
      "Studencka 12, Kraków",
      "nocleg-studencka.pdf",
      Helpers.money!(:PLN, "900.00"),
      monday,
      thursday,
      "Nocleg na 3 noce przy ul. Studenckiej"
    )

    flight_delegation =
      seed_delegation!(
        %{
          title: "Delegacja Kraków - Londyn",
          purpose: "Warsztaty z zespołem w Londynie",
          start_date: friday,
          end_date: sunday,
          advance_payment_amount: Helpers.money!(:PLN, "3000.00")
        },
        kira.id,
        bytecraft.id
      )

    flight_expense =
      seed_transport_expense!(
        flight_delegation.id,
        bytecraft.id,
        "Lot Kraków - Londyn - Kraków",
        "bilet-lotniczy-londyn.pdf",
        Helpers.money!(:PLN, "1250.00"),
        :airplane
      )

    seed_trip!(
      flight_expense.id,
      bytecraft.id,
      "Kraków Airport",
      local_datetime!(friday, ~T[08:00:00]),
      "London Heathrow",
      local_datetime!(friday, ~T[09:30:00])
    )

    seed_trip!(
      flight_expense.id,
      bytecraft.id,
      "London Heathrow",
      local_datetime!(sunday, ~T[20:00:00]),
      "Kraków Airport",
      local_datetime!(sunday, ~T[23:20:00])
    )

    seed_accommodation_expense!(
      flight_delegation.id,
      bytecraft.id,
      "18 Borough High Street, London",
      "nocleg-londyn.pdf",
      Helpers.money!(:PLN, "1400.00"),
      friday,
      sunday,
      "Nocleg na 2 noce w Londynie"
    )

    seed_other_expense!(
      flight_delegation.id,
      bytecraft.id,
      "Transfer lotnisko - hotel",
      "transfer-londyn.pdf",
      Helpers.money!(:PLN, "85.00")
    )
  end

  defp seed_delegation!(attrs, user_id, organization_id) do
    Ash.Seed.seed!(
      Delegation,
      Map.merge(attrs, %{
        billing_month: Date.beginning_of_month(attrs.start_date),
        status: :in_progress,
        user_id: user_id,
        organization_id: organization_id
      }),
      tenant: organization_id
    )
  end

  defp seed_transport_expense!(delegation_id, organization_id, description, filename, amount, type \\ :railway) do
    {:ok, expense} =
      Ash.create(
        DelegationExpenseTransport,
        %{
          delegation_id: delegation_id,
          original_filename: filename,
          document_number: "DEMO-#{delegation_id}",
          expense_amount: amount,
          transport_type: type,
          description: description
        },
        actor: @seed_actor,
        tenant: organization_id
      )

    expense
  end

  defp seed_trip!(
         transport_expense_id,
         organization_id,
         departure_city,
         departure_datetime,
         arrival_city,
         arrival_datetime
       ) do
    trips =
      DelegationTrip
      |> Ash.Query.filter(delegation_expense_transport_id == ^transport_expense_id)
      |> Ash.read!(tenant: organization_id, actor: @seed_actor)

    case trips do
      [%{departure_city: ""} = trip] ->
        Ash.update!(
          trip,
          %{
            departure_city: departure_city,
            departure_datetime: departure_datetime,
            arrival_city: arrival_city,
            arrival_datetime: arrival_datetime
          },
          action: :update,
          actor: @seed_actor,
          tenant: organization_id
        )

      _ ->
        Ash.create!(
          DelegationTrip,
          %{
            delegation_expense_transport_id: transport_expense_id,
            departure_city: departure_city,
            departure_datetime: departure_datetime,
            arrival_city: arrival_city,
            arrival_datetime: arrival_datetime
          },
          actor: @seed_actor,
          tenant: organization_id
        )
    end

    :ok
  end

  defp seed_accommodation_expense!(
         delegation_id,
         organization_id,
         locality,
         filename,
         amount,
         arrival_date,
         departure_date,
         description
       ) do
    Ash.Seed.seed!(
      DelegationExpenseAccommodation,
      %{
        delegation_id: delegation_id,
        organization_id: organization_id,
        original_filename: filename,
        document_number: "DEMO-#{delegation_id}",
        expense_amount: amount,
        locality: locality,
        arrival_date: arrival_date,
        departure_date: departure_date,
        description: description
      },
      tenant: organization_id
    )
  end

  defp seed_other_expense!(delegation_id, organization_id, description, filename, amount) do
    Ash.Seed.seed!(
      DelegationExpenseOther,
      %{
        delegation_id: delegation_id,
        organization_id: organization_id,
        original_filename: filename,
        document_number: "DEMO-#{delegation_id}",
        expense_amount: amount,
        description: description
      },
      tenant: organization_id
    )
  end

  defp next_monday do
    today = Helpers.today()
    Date.add(today, rem(8 - Date.day_of_week(today), 7))
  end

  defp local_datetime!(date, time), do: DateTime.new!(date, time, @timezone)
end
