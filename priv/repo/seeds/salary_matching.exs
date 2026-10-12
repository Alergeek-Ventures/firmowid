defmodule Firmowid.Seeds.SalaryMatching do
  @moduledoc "Reproducible salary-matching demo with amount boundaries and previous-month project hours."

  alias Firmowid.Ash.Core.User
  alias Firmowid.Ash.Payroll.UserSalary
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.Timetracker
  alias Firmowid.Ash.Timetracker.ProjectUser
  alias Firmowid.Ash.Timetracker.Session
  alias Firmowid.Seeds.Helpers

  @doc "Adds demo employees and unmatched transfers without clearing existing assignments."
  @spec seed!(map()) :: [map()]
  def seed!(%{bytecraft: organization, users: %{kira: admin}, bank_accounts: %{pln: bank}, projects: projects}) do
    scope = Scope.new!(admin, organization.id)
    month = Date.utc_today() |> Date.beginning_of_month() |> Date.shift(month: -1)
    booking_date = Date.utc_today()

    employees = [
      {"ada", "Ada Nowak (prototyp)", 3},
      {"jan", "Jan Kowalski (prototyp)", 10},
      {"ewa", "Ewa Zielińska (prototyp)", 50}
    ]

    for {key, name, hours} <- employees do
      user =
        Ash.Seed.upsert!(
          User,
          %{
            email: "pensja.#{key}@bytecraft.collective",
            name: name,
            hashed_password: Argon2.hash_pwd_salt("kolejka123456"),
            organization_id: organization.id,
            role: :employee,
            system_role: :user,
            employment_date: month
          },
          identity: :unique_email
        )

      Ash.Seed.upsert!(
        UserSalary,
        %{
          user_id: user.id,
          organization_id: organization.id,
          hourly_rate: Decimal.new(100),
          starts_at: DateTime.new!(month, ~T[00:00:00], "Etc/UTC")
        },
        identity: :unique_starts_at_per_user,
        tenant: organization.id
      )

      user_projects = Timetracker.list_projects!(%{user_id: user.id}, scope: scope)

      for project <- [projects.firmowid, projects.flatmate],
          not Enum.any?(user_projects, &(&1.id == project.id)) do
        Ash.Seed.seed!(
          ProjectUser,
          %{user_id: user.id, project_id: project.id, organization_id: organization.id},
          tenant: organization.id
        )
      end

      if Timetracker.list_sessions!(%{user_id: user.id, month: month.month, year: month.year},
           scope: scope
         ) == [] do
        1..hours
        |> Enum.chunk_every(5)
        |> Enum.with_index()
        |> Enum.each(fn {chunk, index} ->
          project = if rem(index, 2) == 0, do: projects.firmowid, else: projects.flatmate
          start = DateTime.new!(Date.add(month, index + 1), ~T[09:00:00], "Etc/UTC")

          Ash.Seed.seed!(
            Session,
            %{
              user_id: user.id,
              project_id: project.id,
              organization_id: organization.id,
              title: "Praca do demonstracji przypisywania wynagrodzeń",
              start_datetime: start,
              end_datetime: DateTime.shift(start, hour: length(chunk)),
              is_remote: false
            },
            tenant: organization.id
          )
        end)
      end
    end

    Helpers.get_or_create_cost_invoice(
      "PROTOTYP/FAKTURA/#{Date.beginning_of_month(booking_date)}",
      organization.id,
      %{
        seller: "Jan Kowalski (prototyp)",
        seller_display_name: "Jan Kowalski (prototyp)",
        description: "Prototyp: faktura lub wynagrodzenie dla przelewu 1250 zł",
        account_number: "PL00123456789012345678901234",
        amount: Money.new!(:PLN, -1250),
        sale_date: booking_date,
        issue_date: booking_date,
        due_date: Date.add(booking_date, 14),
        skip_invoicing: false
      }
    )

    for {amount, index} <- Enum.with_index([300, 290, 310], 1) do
      Helpers.get_or_create_cost_invoice(
        "PROTOTYP/ADA/#{index}/#{Date.beginning_of_month(booking_date)}",
        organization.id,
        %{
          seller: "Ada Nowak (prototyp)",
          seller_display_name: "Ada Nowak (prototyp)",
          description: "Prototyp: faktura #{index} lub wynagrodzenie dla przelewu 300 zł",
          account_number: "PL00123456789012345678901234",
          amount: Money.new!(:PLN, -amount),
          sale_date: booking_date,
          issue_date: booking_date,
          due_date: Date.add(booking_date, 14),
          skip_invoicing: false
        }
      )
    end

    scenarios = [
      {"300_dokladna", "Ada Nowak (prototyp)", 300, "300 zł — zgodna kwota"},
      {"300_dolna_granica", "Ada Nowak (prototyp)", 0, "300 zł — dolna granica 0 zł"},
      {"300_gorna_granica", "Ada Nowak (prototyp)", 600, "300 zł — górna granica 600 zł"},
      {"300_poza_granica", "Ada Nowak (prototyp)", 601, "300 zł — poza tolerancją (601 zł)"},
      {"1000_minimum300", "Jan Kowalski (prototyp)", 1250, "1000 zł — różnica 250 zł, minimum tolerancji"},
      {"5000_procent", "Ewa Zielińska (prototyp)", 5900, "5000 zł — różnica 18%"},
      {"5000_poza_granica", "Ewa Zielińska (prototyp)", 6001, "5000 zł — poza tolerancją (6001 zł)"}
    ]

    for {key, name, amount, description} <- scenarios do
      transaction =
        Helpers.seed_transaction!(
          %{
            internal_transaction_id: "prototyp_pensja_#{key}",
            creditor_name: name,
            debtor_name: organization.name,
            debtor_account: bank.iban,
            creditor_account: "PL00123456789012345678901234",
            amount: Money.new!(:PLN, -amount),
            booking_date: booking_date,
            value_date: booking_date,
            remittance_information_unstructured: "PROTOTYP PENSJI: #{description}; wynagrodzenie za #{month}",
            bank_account_id: bank.id
          },
          organization.id
        )

      %{id: transaction.id, scenario: description}
    end
  end
end
