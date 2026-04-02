# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Firmowid.Seeds.Bytecraft do
  @moduledoc """
  Seeds for the primary organization: Bytecraft Collective.
  Creates users, org, counterparties, projects, bank accounts, and a mock blob.
  """

  import Ecto.Query

  alias Firmowid.Accounts
  alias Firmowid.Accounts.Organization
  alias Firmowid.Ash.Invoicing.Counterparty, as: AshCounterparty
  alias Firmowid.Ash.Timetracker.Project, as: AshProject
  alias Firmowid.Repo
  alias Firmowid.SalesInvoices.Counterparty
  alias Firmowid.Seeds.Helpers

  def seed! do
    users = seed_users()
    bytecraft = seed_organization(users.kira)
    Repo.put_org_id(bytecraft.id)
    seed_org_membership(bytecraft, users)
    counterparties = seed_counterparties(bytecraft)
    projects = seed_projects(bytecraft, users, counterparties)
    blob = seed_blob(bytecraft)
    bank_accounts = seed_bank_accounts(bytecraft)

    %{
      users: users,
      bytecraft: bytecraft,
      counterparties: counterparties,
      projects: projects,
      blob: blob,
      bank_accounts: bank_accounts
    }
  end

  # ===========================================================================
  # Users — Bytecraft Collective team
  # ===========================================================================

  defp seed_users do
    register = fn email ->
      case Accounts.register_user(%{email: email, password: "kolejka123456"}) do
        {:ok, user} -> user
        {:error, _} -> Accounts.get_user_by_email(email)
      end
    end

    kira = register.("kira@bytecraft.collective")
    tomek = register.("tomek@bytecraft.collective")
    sable = register.("sable@bytecraft.collective")
    jules = register.("jules@bytecraft.collective")
    maren = register.("maren@bytecraft.collective")

    Accounts.update_user(kira, %{
      system_role: :superuser,
      role: :admin,
      name: "Kira Voss",
      employment_date: ~D[2022-03-01],
      phone: "+48 501 200 300",
      slack_id: "U_KIRA_001",
      bank_account_number: "PL61 1050 0099 7603 1234 5678 9012",
      birthday: ~D[1991-11-07],
      position: "Lead Architect",
      employment_contract_type: :b2b,
      correspondence_street: "ul. Marszałkowska 11/4",
      correspondence_city: "Warszawa",
      correspondence_code: "00-624",
      residence_street: "ul. Marszałkowska 11/4",
      residence_city: "Warszawa",
      residence_code: "00-624"
    })

    Accounts.update_user(tomek, %{
      system_role: :user,
      role: :admin,
      name: "Tomek Briar",
      employment_date: ~D[2022-06-15],
      phone: "+48 502 300 400",
      slack_id: "U_TOMEK_002",
      bank_account_number: "PL27 1140 2004 0000 3002 0135 5387",
      birthday: ~D[1994-04-22],
      position: "Backend Engineer",
      employment_contract_type: :umowa_o_prace,
      correspondence_street: "ul. Świdnicka 36/8",
      correspondence_city: "Wrocław",
      correspondence_code: "50-068",
      residence_street: "ul. Świdnicka 36/8",
      residence_city: "Wrocław",
      residence_code: "50-068"
    })

    Accounts.update_user(sable, %{
      system_role: :user,
      role: :employee,
      name: "Sable Orin",
      employment_date: ~D[2023-01-10],
      phone: "+48 503 400 500",
      slack_id: "U_SABLE_003",
      birthday: ~D[1996-08-14],
      position: "Product Designer",
      employment_contract_type: :umowa_zlecenie,
      student_status_until: ~D[2025-09-30],
      correspondence_street: "ul. Floriańska 22/10",
      correspondence_city: "Kraków",
      correspondence_code: "31-021",
      residence_street: "ul. Floriańska 22/10",
      residence_city: "Kraków",
      residence_code: "31-021"
    })

    Accounts.update_user(jules, %{
      system_role: :user,
      role: :employee,
      name: "Jules Kadar",
      employment_date: ~D[2023-04-01],
      phone: "+48 504 500 600",
      slack_id: "U_JULES_004",
      birthday: ~D[1989-12-03],
      position: "DevOps Lead",
      employment_contract_type: :b2b,
      correspondence_street: "ul. Piotrkowska 80/15",
      correspondence_city: "Łódź",
      correspondence_code: "90-265",
      residence_street: "ul. Piotrkowska 80/15",
      residence_city: "Łódź",
      residence_code: "90-265"
    })

    Accounts.update_user(maren, %{
      system_role: :user,
      role: :employee,
      name: "Maren Solke",
      employment_date: ~D[2023-09-01],
      phone: "+48 505 600 700",
      slack_id: "U_MAREN_005",
      birthday: ~D[1997-02-28],
      position: "Frontend Engineer",
      employment_contract_type: :umowa_o_prace,
      correspondence_street: "ul. Długa 45/2",
      correspondence_city: "Gdańsk",
      correspondence_code: "80-831",
      residence_street: "ul. Długa 45/2",
      residence_city: "Gdańsk",
      residence_code: "80-831"
    })

    %{kira: kira, tomek: tomek, sable: sable, jules: jules, maren: maren}
  end

  # ===========================================================================
  # Organization — Bytecraft Collective
  # ===========================================================================

  defp seed_organization(kira) do
    case Repo.one(
           from(o in Organization, where: o.nip == "6161525811", limit: 1),
           skip_organization_id: true
         ) do
      nil ->
        {:ok, org} =
          Accounts.create_organization(
            %{
              "name" => "Bytecraft Collective spółka z ograniczoną odpowiedzialnością",
              "nip" => "6161525811",
              "address" => "ul. Marszałkowska 11/4, 00-624 Warszawa",
              "owner_id" => kira.id
            },
            kira
          )

        org

      org ->
        org
    end
  end

  defp seed_org_membership(bytecraft, users) do
    for user <- [users.tomek, users.sable, users.jules, users.maren] do
      if is_nil(user.organization_id) or user.organization_id != bytecraft.id do
        case Accounts.create_organization_invites(bytecraft.id, users.kira.id) do
          {:ok, invite} -> Accounts.consume_organization_invite(invite.invite_code, user.id)
          {:error, _} -> :ok
        end
      end
    end
  end

  # ===========================================================================
  # Counterparties
  # ===========================================================================

  defp seed_counterparties(bytecraft) do
    get_or_create = fn attrs ->
      existing =
        cond do
          attrs[:tax_id] && attrs[:tax_id] != "" ->
            Repo.one(
              from(c in Counterparty,
                where: c.tax_id == ^attrs[:tax_id] and c.organization_id == ^bytecraft.id,
                limit: 1
              )
            )

          attrs[:display_name] ->
            Repo.one(
              from(c in Counterparty,
                where:
                  c.display_name == ^attrs[:display_name] and
                    c.organization_id == ^bytecraft.id,
                limit: 1
              )
            )

          true ->
            nil
        end

      case existing do
        # TODO: replace authorize?: false + actor: %{} with system actor once available
        nil -> AshCounterparty.create(attrs, tenant: bytecraft.id, authorize?: false, actor: %{})
        counterparty -> {:ok, counterparty}
      end
    end

    {:ok, ghostpet} =
      get_or_create.(%{
        type: :company,
        tax_id: "US-EIN-47-8830291",
        full_name: "GhostPet Inc.",
        display_name: "GhostPet",
        address: "440 N Barranca Ave #7658\nCovina, CA 91723",
        country: "US",
        email: "billing@ghostpet.ai",
        phone: "+1 626 555 0147",
        description: "AI conversations with deceased pets. The parrot module is haunted."
      })

    {:ok, flatearth} =
      get_or_create.(%{
        type: :company,
        full_name: "FlatEarth Dating Ltd.",
        display_name: "FlatMate",
        address: "17 Fictitious Lane\nLondon EC2A 4NE",
        country: "GB",
        email: "accounts@flatmate.earth",
        phone: "+44 20 7946 0958",
        description: "Dating app for flat earthers. Kira built the disc map. 200k users."
      })

    {:ok, taco} =
      get_or_create.(%{
        type: :company,
        tax_id: "DE317256842",
        full_name: "TacoOverflow Inc.",
        display_name: "TacoOverflow",
        address: "Friedrichstraße 123\n10117 Berlin",
        country: "DE",
        email: "invoices@tacooverflow.dev",
        phone: "+49 30 555 0199",
        description: "Stack Overflow clone but with taco recipes. Deployed on a Raspberry Pi taped to a microwave."
      })

    %{ghostpet: ghostpet, flatearth: flatearth, taco: taco}
  end

  # ===========================================================================
  # Projects
  # ===========================================================================

  defp seed_projects(bytecraft, users, counterparties) do
    tenant = bytecraft.id

    get_or_create = fn name, counterparty_id ->
      case Repo.one(
             from(p in AshProject,
               where: p.name == ^name and p.organization_id == ^tenant,
               limit: 1
             )
           ) do
        nil ->
          params =
            then(%{name: name}, fn p -> if counterparty_id, do: Map.put(p, :counterparty_id, counterparty_id), else: p end)

          {:ok, project} = AshProject.create(params, tenant: tenant, authorize?: false, actor: %{})
          project

        project ->
          project
      end
    end

    firmowid = get_or_create.("Firmowid", nil)
    ghostpet = get_or_create.("GhostPet", counterparties.ghostpet.id)
    flatmate = get_or_create.("FlatMate", counterparties.flatearth.id)
    taco = get_or_create.("TacoOverflow", counterparties.taco.id)

    project_users = %{
      firmowid => [users.kira.id, users.tomek.id],
      ghostpet => [users.tomek.id, users.maren.id],
      flatmate => [users.kira.id, users.sable.id],
      taco => [users.jules.id, users.maren.id, users.tomek.id]
    }

    for {project, user_ids} <- project_users do
      {:ok, _} =
        AshProject.set_users(user_ids, %{project_id: project.id},
          tenant: tenant,
          authorize?: false,
          actor: %{}
        )
    end

    projects = %{firmowid: firmowid, ghostpet: ghostpet, flatmate: flatmate, taco: taco}

    # Preload tag definitions for use in tagging
    Map.new(projects, fn {key, project} ->
      {key, Repo.preload(project, :tag_definition)}
    end)
  end

  # ===========================================================================
  # Mock blob (placeholder PDF for cost invoices)
  # ===========================================================================

  defp seed_blob(bytecraft) do
    Helpers.seed_blob!(
      %{
        blob_path: "4ff0d0b1-3298-4b80-9d53-a71d0efc4cad/seed-invoice-placeholder.pdf",
        blob_checksum: "ff2c9062d9a8189522a59805210ebe5d2211e5868d724a47863a0b740d6892b6",
        original_filename: "seed-invoice-placeholder.pdf"
      },
      bytecraft.id
    )
  end

  # ===========================================================================
  # Bank accounts — 5 currencies across 2 institutions
  # ===========================================================================

  defp seed_bank_accounts(bytecraft) do
    tenant = bytecraft.id

    mock_requisition =
      Helpers.seed_requisition!("b42a914c-d658-46bb-ab4c-950967fbebe1", tenant)

    ing_base = %{
      institution_id: "ING_BANK_SLASKI_PL",
      institution_name: "ING Bank Śląski",
      owner_name: "Bytecraft Collective sp. z o.o.",
      requisition_id: mock_requisition.id
    }

    pln =
      Helpers.seed_bank_account!(
        Map.merge(ing_base, %{
          iban: "PL61105000997603123456789012",
          gocardless_id: "c5831186-ca3e-4edc-a4f5-a48b1d1ead51",
          currency: "PLN",
          is_default: true
        }),
        tenant
      )

    eur =
      Helpers.seed_bank_account!(
        Map.merge(ing_base, %{
          iban: "PL85105000997603123456789013",
          gocardless_id: "c5831186-ca3e-4edc-a4f5-a48b1d1ead52",
          currency: "EUR",
          is_default: false
        }),
        tenant
      )

    usd =
      Helpers.seed_bank_account!(
        Map.merge(ing_base, %{
          iban: "PL42105000997603123456789014",
          gocardless_id: "c5831186-ca3e-4edc-a4f5-a48b1d1ead53",
          currency: "USD",
          is_default: false
        }),
        tenant
      )

    gbp =
      Helpers.seed_bank_account!(
        Map.merge(ing_base, %{
          iban: "PL19105000997603123456789015",
          gocardless_id: "c5831186-ca3e-4edc-a4f5-a48b1d1ead54",
          currency: "GBP",
          is_default: false
        }),
        tenant
      )

    thb =
      Helpers.seed_bank_account!(
        %{
          iban: "PL73116022020000000512345678",
          institution_id: "MILLENNIUM_BANK_PL",
          institution_name: "Bank Millennium",
          owner_name: "Bytecraft Collective sp. z o.o.",
          gocardless_id: "c5831186-ca3e-4edc-a4f5-a48b1d1ead55",
          currency: "THB",
          is_default: false,
          requisition_id: mock_requisition.id
        },
        tenant
      )

    %{pln: pln, eur: eur, usd: usd, gbp: gbp, thb: thb}
  end
end
