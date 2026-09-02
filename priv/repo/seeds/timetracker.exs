# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Firmowid.Seeds.Timetracker do
  @moduledoc """
  Seeds for the timetracker: salaries, time tracking sessions, and hours records.

  Creates:
  - Active employment contract for each employee (Sable has pending_signature for signing flow)
  - Active salary for each employee (+ one historical entry for Kira), linked to contracts
  - Sessions for M-2 and M-1 (completed months, locked down by hours records)
  - Sessions for M-0 (current month, open — no hours record)
  - Hours records for M-2 and M-1 (with placeholder blob attachments)
  - No hours records for M-0 (so the upload wizard is testable)
  """

  alias Firmowid.Ash.Payroll.UserEmploymentContract
  alias Firmowid.Ash.Payroll.UserSalary
  alias Firmowid.Ash.Timetracker.HoursRecord
  alias Firmowid.Ash.Timetracker.Session
  alias Firmowid.Seeds.Helpers

  require Ash.Query

  @seed_actor %{id: "00000000-0000-0000-0000-000000000000", role: :admin}

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def seed!(ctx) do
    contracts_by_user_id = seed_employment_contracts(ctx)
    seed_salaries(ctx, contracts_by_user_id)
    seed_sessions_m2(ctx)
    seed_sessions_m1(ctx)
    seed_sessions_m0(ctx)
    seed_hours_records(ctx)
  end

  # ---------------------------------------------------------------------------
  # Employment contracts
  # ---------------------------------------------------------------------------

  defp seed_employment_contracts(ctx) do
    %{users: users, bytecraft: bytecraft} = ctx
    org_id = bytecraft.id

    contract_specs = [
      {users.kira,
       %{
         position: "Lead Engineer",
         contract_type: :uop,
         status: :active,
         hourly_rate: Decimal.new("150.00")
       }},
      {users.tomek,
       %{
         position: "Accountant",
         contract_type: :uop,
         status: :active,
         hourly_rate: Decimal.new("120.00")
       }},
      {users.sable,
       %{
         position: "Product Designer",
         contract_type: :uz,
         status: :pending_signature,
         hourly_rate: Decimal.new("100.00")
       }},
      {users.jules,
       %{
         position: "DevOps Engineer",
         contract_type: :b2b,
         status: :active,
         hourly_rate: Decimal.new("130.00")
       }},
      {users.maren,
       %{
         position: "Frontend Developer",
         contract_type: :uop,
         status: :active,
         hourly_rate: Decimal.new("110.00")
       }}
    ]

    Enum.reduce(contract_specs, %{}, fn {user, spec}, acc ->
      contract = seed_employment_contract!(user, org_id, spec)
      Map.put(acc, user.id, contract.id)
    end)
  end

  defp seed_employment_contract!(user, org_id, spec) do
    starts_at = user.employment_date || Date.utc_today()

    signed_at =
      if spec.status == :pending_signature do
        Date.add(Date.utc_today(), 14)
      else
        starts_at
      end

    checksum =
      :sha256
      |> :crypto.hash("employment-contract:#{user.id}:#{org_id}")
      |> Base.encode16(case: :lower)

    blob =
      Helpers.seed_blob!(
        %{
          blob_path: "employment-contracts/#{user.id}/umowa.pdf",
          blob_checksum: checksum,
          original_filename: "umowa.pdf"
        },
        org_id
      )

    Ash.Seed.upsert!(
      UserEmploymentContract,
      %{
        user_id: user.id,
        organization_id: org_id,
        starts_at: starts_at,
        salary: contract_salary!(spec.hourly_rate),
        blob_id: blob.id,
        contract_type: spec.contract_type,
        position: spec.position,
        status: spec.status,
        signed_at: signed_at
      },
      identity: :unique_contract_per_user_org,
      tenant: org_id
    )
  end

  defp contract_salary!(hourly_rate) do
    Helpers.money!("PLN", Decimal.mult(hourly_rate, 160))
  end

  # ---------------------------------------------------------------------------
  # Salaries
  # ---------------------------------------------------------------------------

  defp seed_salaries(ctx, contracts_by_user_id) do
    %{users: users, bytecraft: bytecraft} = ctx

    salary_data = [
      {users.kira, Decimal.new("150.00")},
      {users.tomek, Decimal.new("120.00")},
      {users.sable, Decimal.new("100.00")},
      {users.jules, Decimal.new("130.00")},
      {users.maren, Decimal.new("110.00")}
    ]

    for {user, rate} <- salary_data do
      get_or_create_salary(user.id, bytecraft.id, rate, Map.get(contracts_by_user_id, user.id))
    end

    # Historical salary for Kira — she got a raise from 120 to 150
    create_historical_salary(users.kira.id, bytecraft.id, Decimal.new("120.00"))
  end

  defp get_or_create_salary(user_id, org_id, hourly_rate, employment_contract_id \\ nil) do
    attrs =
      %{
        hourly_rate: hourly_rate,
        user_id: user_id,
        organization_id: org_id,
        starts_at: DateTime.utc_now()
      }
      |> maybe_put_employment_contract_id(employment_contract_id)

    Ash.Seed.seed!(
      UserSalary,
      attrs,
      tenant: org_id
    )
  end

  defp maybe_put_employment_contract_id(attrs, nil), do: attrs

  defp maybe_put_employment_contract_id(attrs, employment_contract_id) do
    Map.put(attrs, :employment_contract_id, employment_contract_id)
  end

  defp create_historical_salary(user_id, org_id, hourly_rate) do
    three_months_ago = Helpers.months_ago(3)
    one_month_ago = Helpers.months_ago(1)

    started = DateTime.new!(three_months_ago, ~T[09:00:00], "Etc/UTC")
    ended = DateTime.new!(Date.beginning_of_month(one_month_ago), ~T[09:00:00], "Etc/UTC")

    Ash.Seed.seed!(
      UserSalary,
      %{
        hourly_rate: hourly_rate,
        starts_at: Date.beginning_of_month(one_month_ago),
        user_id: user_id,
        organization_id: org_id,
        inserted_at: started,
        updated_at: ended
      },
      tenant: org_id
    )
  end

  # ---------------------------------------------------------------------------
  # Sessions — M-2 (2 months ago)
  # ---------------------------------------------------------------------------

  defp seed_sessions_m2(ctx) do
    %{users: users, projects: projects, bytecraft: bytecraft} = ctx

    m2_sessions = [
      # Kira — Firmowid (code reviews, architecture)
      session_attrs(users.kira, projects.firmowid, "Przegląd kodu — moduł faktur", 2, 3, 9, 0, 12, 0, false),
      session_attrs(users.kira, projects.firmowid, "Architektura — integracja KSeF", 2, 5, 10, 0, 14, 0, true),
      session_attrs(users.kira, projects.firmowid, "Refaktoring — warstwa persystencji", 2, 7, 9, 0, 11, 30, false),
      # Kira — FlatMate (disc map, sprint 7-8)
      session_attrs(users.kira, projects.flatmate, "Mapa dysku — algorytm renderowania", 2, 4, 9, 0, 14, 0, true),
      session_attrs(users.kira, projects.flatmate, "Mapa dysku — optymalizacja WebGL", 2, 6, 10, 0, 15, 0, true),
      session_attrs(users.kira, projects.flatmate, "FlatMate sprint 7 — review & merge", 2, 8, 9, 0, 12, 0, false),
      session_attrs(users.kira, projects.flatmate, "FlatMate sprint 8 — planowanie", 2, 10, 13, 0, 16, 0, true),
      session_attrs(users.kira, projects.flatmate, "Algorytm dopasowań — testy integracyjne", 2, 12, 9, 0, 13, 0, false),
      # Tomek — Firmowid
      session_attrs(users.tomek, projects.firmowid, "Migracje bazy danych — nowe indeksy", 2, 3, 9, 0, 12, 0, false),
      session_attrs(users.tomek, projects.firmowid, "Testy jednostkowe — moduł płatności", 2, 9, 10, 0, 14, 0, true),
      # Tomek — GhostPet (AI conversation platform)
      session_attrs(users.tomek, projects.ghostpet, "API konwersacji — endpoint czatu", 2, 4, 9, 0, 13, 0, false),
      session_attrs(users.tomek, projects.ghostpet, "Model NLP — trenowanie na danych zwierząt", 2, 5, 9, 0, 14, 0, true),
      session_attrs(users.tomek, projects.ghostpet, "Pipeline audio — synteza mowy zwierząt", 2, 6, 10, 0, 15, 0, false),
      session_attrs(users.tomek, projects.ghostpet, "Integracja z bazą wspomnień", 2, 8, 9, 0, 13, 0, true),
      session_attrs(users.tomek, projects.ghostpet, "GhostPet — poprawki bugów w czacie", 2, 10, 9, 0, 11, 0, false),
      # Tomek — TacoOverflow
      session_attrs(users.tomek, projects.taco, "Backend — system ocen pikantności", 2, 7, 9, 0, 14, 0, false),
      session_attrs(users.tomek, projects.taco, "API wyszukiwania przepisów", 2, 11, 10, 0, 15, 0, true),
      # Sable — FlatMate (design)
      session_attrs(users.sable, projects.flatmate, "Mockupy UI — profil użytkownika", 2, 3, 9, 0, 13, 0, true),
      session_attrs(users.sable, projects.flatmate, "Projekt interfejsu — ekran dopasowań", 2, 5, 10, 0, 14, 0, false),
      session_attrs(users.sable, projects.flatmate, "Design system — komponenty FlatMate", 2, 7, 9, 0, 12, 0, true),
      session_attrs(users.sable, projects.flatmate, "Testy użyteczności — nawigacja mapą", 2, 9, 10, 0, 15, 0, false),
      session_attrs(users.sable, projects.flatmate, "Ikony i grafiki — flat earth theme", 2, 11, 9, 0, 12, 0, true),
      # Jules — TacoOverflow
      session_attrs(users.jules, projects.taco, "Infrastruktura — deploy na Raspberry Pi", 2, 3, 9, 0, 14, 0, false),
      session_attrs(users.jules, projects.taco, "CI/CD pipeline — testy na mikrofali", 2, 5, 10, 0, 15, 0, true),
      session_attrs(users.jules, projects.taco, "Monitoring — Grafana dashboardy", 2, 7, 9, 0, 13, 0, false),
      session_attrs(users.jules, projects.taco, "Konfiguracja Kubernetes — klaster taco", 2, 9, 10, 0, 15, 0, true),
      session_attrs(users.jules, projects.taco, "Backup bazy danych — procedury DR", 2, 11, 9, 0, 12, 0, false),
      session_attrs(users.jules, projects.taco, "Optymalizacja sieci — edge caching", 2, 12, 13, 0, 17, 0, true),
      # Maren — GhostPet (frontend)
      session_attrs(users.maren, projects.ghostpet, "Frontend czatu — komponent konwersacji", 2, 3, 9, 0, 13, 0, true),
      session_attrs(users.maren, projects.ghostpet, "Animacje — avatar zwierzaka", 2, 5, 10, 0, 14, 0, false),
      session_attrs(users.maren, projects.ghostpet, "Responsywność — widok mobilny", 2, 7, 9, 0, 12, 0, true),
      session_attrs(users.maren, projects.ghostpet, "Integracja API — websockety", 2, 9, 10, 0, 14, 0, false),
      # Maren — TacoOverflow
      session_attrs(users.maren, projects.taco, "Frontend — strona z przepisami", 2, 4, 9, 0, 13, 0, true),
      session_attrs(users.maren, projects.taco, "Komponent ocen — gwiazdki pikantności", 2, 6, 10, 0, 14, 0, false),
      session_attrs(users.maren, projects.taco, "Formularz dodawania przepisu", 2, 10, 9, 0, 13, 0, true),
      session_attrs(users.maren, projects.taco, "TacoOverflow — poprawki CSS", 2, 12, 10, 0, 12, 0, false)
    ]

    insert_sessions(m2_sessions, bytecraft)
  end

  # ---------------------------------------------------------------------------
  # Sessions — M-1 (1 month ago)
  # ---------------------------------------------------------------------------

  defp seed_sessions_m1(ctx) do
    %{users: users, projects: projects, bytecraft: bytecraft} = ctx

    m1_sessions = [
      # Kira — Firmowid
      session_attrs(users.kira, projects.firmowid, "Przegląd PR — tagowanie analiz", 1, 2, 9, 0, 12, 0, true),
      session_attrs(users.kira, projects.firmowid, "Planowanie sprintu — Q2 roadmap", 1, 8, 14, 0, 17, 0, false),
      # Kira — FlatMate
      session_attrs(users.kira, projects.flatmate, "Edge-of-disc — system powiadomień", 1, 3, 9, 0, 14, 0, true),
      session_attrs(users.kira, projects.flatmate, "Udostępnianie lokalizacji — backend", 1, 5, 10, 0, 15, 0, false),
      session_attrs(users.kira, projects.flatmate, "FlatMate — bugfix lokalizacji GPS", 1, 7, 9, 0, 11, 0, true),
      session_attrs(users.kira, projects.flatmate, "Optymalizacja zapytań — mapa dysku", 1, 9, 10, 0, 14, 0, false),
      # Tomek — Firmowid
      session_attrs(users.tomek, projects.firmowid, "Optymalizacja zapytań SQL", 1, 4, 9, 0, 12, 0, true),
      # Tomek — GhostPet (parrot module)
      session_attrs(users.tomek, projects.ghostpet, "Moduł papugi — silnik konwersacji", 1, 2, 9, 0, 14, 0, false),
      session_attrs(users.tomek, projects.ghostpet, "AI żałoby — dostrajanie modelu", 1, 3, 10, 0, 15, 0, true),
      session_attrs(users.tomek, projects.ghostpet, "Pipeline danych — import wspomnień", 1, 5, 9, 0, 13, 0, false),
      session_attrs(users.tomek, projects.ghostpet, "GhostPet — naprawka memory leaks", 1, 7, 10, 0, 14, 0, true),
      session_attrs(users.tomek, projects.ghostpet, "Testy wydajnościowe — obciążenie API", 1, 9, 9, 0, 12, 0, false),
      # Tomek — TacoOverflow
      session_attrs(users.tomek, projects.taco, "System odznak — hot sauce badges", 1, 6, 9, 0, 13, 0, true),
      session_attrs(users.tomek, projects.taco, "Przygotowanie do Series A — demo API", 1, 10, 10, 0, 15, 0, false),
      # Sable — FlatMate
      session_attrs(users.sable, projects.flatmate, "Redesign — ekran powiadomień", 1, 2, 9, 0, 13, 0, false),
      session_attrs(users.sable, projects.flatmate, "Prototypy — udostępnianie lokalizacji", 1, 4, 10, 0, 15, 0, true),
      session_attrs(users.sable, projects.flatmate, "Testy A/B — nowy onboarding", 1, 6, 9, 0, 12, 0, false),
      session_attrs(users.sable, projects.flatmate, "Grafiki marketingowe — kampania Q2", 1, 8, 10, 0, 14, 0, true),
      session_attrs(users.sable, projects.flatmate, "Aktualizacja design systemu", 1, 10, 9, 0, 12, 0, false),
      # Jules — TacoOverflow
      session_attrs(users.jules, projects.taco, "Migracja serwera — z Pi na Pi 5", 1, 2, 9, 0, 14, 0, false),
      session_attrs(users.jules, projects.taco, "Konfiguracja SSL — certyfikaty", 1, 4, 10, 0, 14, 0, true),
      session_attrs(users.jules, projects.taco, "Load balancing — przygotowanie do ruchu", 1, 6, 9, 0, 13, 0, false),
      session_attrs(users.jules, projects.taco, "Automatyzacja deploymentu — Ansible", 1, 8, 10, 0, 15, 0, true),
      session_attrs(users.jules, projects.taco, "Audyt bezpieczeństwa — penetration test", 1, 10, 9, 0, 13, 0, false),
      # Maren — GhostPet
      session_attrs(users.maren, projects.ghostpet, "Frontend — nowy widok czatu papugi", 1, 2, 9, 0, 13, 0, true),
      session_attrs(users.maren, projects.ghostpet, "Animacje emocji — reakcje AI", 1, 4, 10, 0, 14, 0, false),
      session_attrs(users.maren, projects.ghostpet, "Dashboard użytkownika — statystyki", 1, 8, 9, 0, 12, 0, true),
      # Maren — TacoOverflow
      session_attrs(users.maren, projects.taco, "Frontend — system odznak", 1, 3, 9, 0, 13, 0, false),
      session_attrs(users.maren, projects.taco, "Strona Series A — landing page", 1, 5, 10, 0, 14, 0, true),
      session_attrs(users.maren, projects.taco, "Responsywność — widok tabletu", 1, 9, 9, 0, 12, 0, false)
    ]

    insert_sessions(m1_sessions, bytecraft)
  end

  # ---------------------------------------------------------------------------
  # Sessions — M-0 (current month — no hours record, open for editing)
  # ---------------------------------------------------------------------------

  defp seed_sessions_m0(ctx) do
    %{users: users, projects: projects, bytecraft: bytecraft} = ctx

    # Fewer sessions — month is "in progress"
    m0_sessions = [
      # Kira — Firmowid
      session_attrs(users.kira, projects.firmowid, "Standup — planowanie tygodnia", 0, 3, 9, 0, 10, 0, true),
      session_attrs(users.kira, projects.firmowid, "Code review — moduł analizy", 0, 5, 10, 0, 13, 0, false),
      # Kira — FlatMate
      session_attrs(users.kira, projects.flatmate, "Hotfix — crash mapy na iOS", 0, 4, 14, 0, 17, 0, true),
      # Tomek — GhostPet
      session_attrs(users.tomek, projects.ghostpet, "Silnik konwersacji — nowe funkcje", 0, 3, 9, 0, 14, 0, false),
      session_attrs(users.tomek, projects.ghostpet, "Debugowanie — problem z pamięcią", 0, 5, 10, 0, 13, 0, true),
      # Tomek — TacoOverflow
      session_attrs(users.tomek, projects.taco, "Series A — sprint końcowy", 0, 4, 9, 0, 13, 0, false),
      # Sable — FlatMate
      session_attrs(users.sable, projects.flatmate, "Nowe ikony — aktualizacja zestawu", 0, 3, 9, 0, 12, 0, true),
      session_attrs(users.sable, projects.flatmate, "Przegląd UX — flow rejestracji", 0, 5, 10, 0, 14, 0, false),
      # Jules — TacoOverflow
      session_attrs(users.jules, projects.taco, "Deploy — nowa wersja na Pi 5", 0, 3, 9, 0, 12, 0, false),
      session_attrs(users.jules, projects.taco, "Monitoring — alerty Slack", 0, 5, 10, 0, 13, 0, true),
      # Maren — GhostPet
      session_attrs(users.maren, projects.ghostpet, "Poprawki CSS — widok mobilny", 0, 3, 9, 0, 12, 0, true),
      # Maren — TacoOverflow
      session_attrs(users.maren, projects.taco, "Landing page — poprawki copy", 0, 4, 10, 0, 13, 0, false)
    ]

    insert_sessions(m0_sessions, bytecraft)
  end

  # ---------------------------------------------------------------------------
  # Hours records — M-2 and M-1 only (M-0 left open for testing)
  # ---------------------------------------------------------------------------

  defp seed_hours_records(ctx) do
    %{users: users, bytecraft: bytecraft} = ctx

    for months_back <- [2, 1] do
      ref_date = Helpers.months_ago(months_back)

      for user <- [users.kira, users.tomek, users.sable, users.jules, users.maren] do
        hours = count_user_hours(user.id, bytecraft.id, ref_date.month, ref_date.year)

        if hours > 0 do
          get_or_create_hours_record(
            user.id,
            bytecraft.id,
            ref_date.month,
            ref_date.year,
            hours
          )
        end
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp session_attrs(user, project, title, months_back, day, start_h, start_m, end_h, end_m, remote) do
    ref = if months_back == 0, do: Helpers.today(), else: Helpers.months_ago(months_back)
    date = Date.new!(ref.year, ref.month, min(day, Date.days_in_month(ref)))

    start_dt = DateTime.new!(date, Time.new!(start_h, start_m, 0), "Etc/UTC")
    end_dt = DateTime.new!(date, Time.new!(end_h, end_m, 0), "Etc/UTC")

    %{
      user_id: user.id,
      project_id: project.id,
      title: title,
      start_datetime: start_dt,
      end_datetime: end_dt,
      is_remote: remote
    }
  end

  defp insert_sessions(session_list, bytecraft) do
    for attrs <- session_list do
      Ash.Seed.seed!(
        Session,
        %{
          title: attrs.title,
          start_datetime: attrs.start_datetime,
          end_datetime: attrs.end_datetime,
          is_remote: attrs.is_remote,
          user_id: attrs.user_id,
          project_id: attrs.project_id,
          organization_id: bytecraft.id
        },
        tenant: bytecraft.id
      )
    end
  end

  defp count_user_hours(user_id, org_id, month, year) do
    start_date = Date.new!(year, month, 1)
    end_date = Date.end_of_month(start_date)

    start_dt = DateTime.new!(start_date, ~T[00:00:00], "Etc/UTC")
    end_dt = DateTime.new!(end_date, ~T[23:59:59], "Etc/UTC")

    query =
      Ash.Query.filter(
        Session,
        user_id == ^user_id and
          organization_id == ^org_id and
          not is_nil(end_datetime) and
          start_datetime >= ^start_dt and
          start_datetime <= ^end_dt
      )

    sessions = Ash.read!(query, tenant: org_id, actor: @seed_actor)

    total_seconds =
      Enum.reduce(sessions, 0, fn s, acc ->
        acc + DateTime.diff(s.end_datetime, s.start_datetime, :second)
      end)

    # ceil to whole hours, matching the app's TimeConverter logic
    (total_seconds / 3600) |> Float.ceil() |> trunc()
  end

  defp get_or_create_hours_record(user_id, org_id, month, year, hours) do
    # Create a placeholder blob for the signed hours PDF
    checksum = Base.encode16(:crypto.hash(:sha256, "hours-#{user_id}-#{month}-#{year}"), case: :lower)
    blob_path = "hours-records/#{user_id}/#{year}-#{month}/ewidencja-#{month}-#{year}.pdf"

    blob =
      Helpers.seed_blob!(
        %{
          blob_path: blob_path,
          blob_checksum: checksum,
          original_filename: "ewidencja-#{month}-#{year}.pdf"
        },
        org_id
      )

    Ash.Seed.upsert!(
      HoursRecord,
      %{
        month: month,
        year: year,
        number_of_hours: hours,
        blob_id: blob.id,
        user_id: user_id,
        organization_id: org_id
      },
      identity: :unique_month_year_user,
      tenant: org_id
    )
  end
end
