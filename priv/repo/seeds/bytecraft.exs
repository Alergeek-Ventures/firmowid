# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Firmowid.Seeds.Bytecraft do
  @moduledoc """
  Seeds for the primary organization: Bytecraft Collective.
  Creates users, org, counterparties, projects, bank accounts, and a mock blob.
  """

  alias Firmowid.Ash.Analysis.TagDefinition, as: AshTagDefinition
  alias Firmowid.Ash.Core.Organization, as: CoreOrganization
  alias Firmowid.Ash.Core.User, as: CoreUser
  alias Firmowid.Ash.Invoicing.Counterparty, as: AshCounterparty
  alias Firmowid.Ash.Ksef.Credential
  alias Firmowid.Ash.Timetracker.Project, as: AshProject
  alias Firmowid.Ash.Timetracker.ProjectUser, as: AshProjectUser
  alias Firmowid.Seeds.Helpers

  require Ash.Query

  @seed_actor %{id: "00000000-0000-0000-0000-000000000000", role: :admin}

  def seed! do
    users = seed_users()
    bytecraft = seed_organization(users.kira)
    seed_org_membership(bytecraft, users)
    counterparties = seed_counterparties(bytecraft)
    projects = seed_projects(bytecraft, users, counterparties)
    blob = seed_blob(bytecraft)
    seed_ksef_credential(bytecraft)
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
      Ash.Seed.upsert!(
        CoreUser,
        %{email: email, hashed_password: Argon2.hash_pwd_salt("kolejka123456")},
        identity: :unique_email
      )
    end

    kira = register.("kira@bytecraft.collective")
    tomek = register.("tomek@bytecraft.collective")
    sable = register.("sable@bytecraft.collective")
    jules = register.("jules@bytecraft.collective")
    maren = register.("maren@bytecraft.collective")

    kira =
      Ash.Seed.update!(kira, %{
        system_role: :superuser,
        role: :admin,
        name: "Kira Voss",
        employment_date: ~D[2022-03-01],
        phone: "+48 501 200 300",
        slack_id: "U_KIRA_001",
        bank_account_number: "PL61 1050 0099 7603 1234 5678 9012",
        birthday: ~D[1991-11-07],
        position: "Lead Architect",
        correspondence_street: "ul. Marszałkowska 11/4",
        correspondence_city: "Warszawa",
        correspondence_code: "00-624",
        residence_street: "ul. Marszałkowska 11/4",
        residence_city: "Warszawa",
        residence_code: "00-624"
      })

    tomek =
      Ash.Seed.update!(tomek, %{
        system_role: :user,
        role: :accountant,
        name: "Tomek Briar",
        employment_date: ~D[2022-06-15],
        phone: "+48 502 300 400",
        slack_id: "U_TOMEK_002",
        bank_account_number: "PL27 1140 2004 0000 3002 0135 5387",
        birthday: ~D[1994-04-22],
        position: "Backend Engineer",
        correspondence_street: "ul. Świdnicka 36/8",
        correspondence_city: "Wrocław",
        correspondence_code: "50-068",
        residence_street: "ul. Świdnicka 36/8",
        residence_city: "Wrocław",
        residence_code: "50-068"
      })

    sable =
      Ash.Seed.update!(sable, %{
        system_role: :user,
        role: :employee,
        name: "Sable Orin",
        employment_date: ~D[2023-01-10],
        phone: "+48 503 400 500",
        slack_id: "U_SABLE_003",
        birthday: ~D[1996-08-14],
        position: "Product Designer",
        correspondence_street: "ul. Floriańska 22/10",
        correspondence_city: "Kraków",
        correspondence_code: "31-021",
        residence_street: "ul. Floriańska 22/10",
        residence_city: "Kraków",
        residence_code: "31-021"
      })

    jules =
      Ash.Seed.update!(jules, %{
        system_role: :user,
        role: :invoicing,
        name: "Jules Kadar",
        employment_date: ~D[2023-04-01],
        phone: "+48 504 500 600",
        slack_id: "U_JULES_004",
        birthday: ~D[1989-12-03],
        position: "DevOps Lead",
        correspondence_street: "ul. Piotrkowska 80/15",
        correspondence_city: "Łódź",
        correspondence_code: "90-265",
        residence_street: "ul. Piotrkowska 80/15",
        residence_city: "Łódź",
        residence_code: "90-265"
      })

    maren =
      Ash.Seed.update!(maren, %{
        system_role: :user,
        role: :employee,
        name: "Maren Solke",
        employment_date: ~D[2023-09-01],
        phone: "+48 505 600 700",
        slack_id: "U_MAREN_005",
        birthday: ~D[1997-02-28],
        position: "Frontend Engineer",
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
    Ash.Seed.upsert!(
      CoreOrganization,
      %{
        name: "Bytecraft Collective spółka z ograniczoną odpowiedzialnością",
        nip: "6161525811",
        address: "ul. Marszałkowska 11/4, 00-624 Warszawa",
        owner_id: kira.id,
        inbound_email_nickname: "bytecraft"
      },
      identity: :unique_nickname
    )
  end

  defp seed_org_membership(bytecraft, users) do
    for user <- [users.kira, users.tomek, users.sable, users.jules, users.maren] do
      if is_nil(user.organization_id) or user.organization_id != bytecraft.id do
        Ash.Seed.update!(user, %{organization_id: bytecraft.id})
      end
    end
  end

  # ===========================================================================
  # Counterparties
  # ===========================================================================

  defp seed_counterparties(bytecraft) do
    ghostpet =
      get_or_seed_counterparty!(bytecraft.id, %{
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

    flatearth =
      get_or_seed_counterparty!(bytecraft.id, %{
        type: :company,
        full_name: "FlatEarth Dating Ltd.",
        display_name: "FlatMate",
        address: "17 Fictitious Lane\nLondon EC2A 4NE",
        country: "GB",
        email: "accounts@flatmate.earth",
        phone: "+44 20 7946 0958",
        description: "Dating app for flat earthers. Kira built the disc map. 200k users."
      })

    taco =
      get_or_seed_counterparty!(bytecraft.id, %{
        type: :company,
        tax_id: "317256842",
        full_name: "TacoOverflow Inc.",
        display_name: "TacoOverflow",
        address: "Friedrichstraße 123\n10117 Berlin",
        country: "DE",
        email: "invoices@tacooverflow.dev",
        phone: "+49 30 555 0199",
        description: "Stack Overflow clone but with taco recipes. Deployed on a Raspberry Pi taped to a microwave."
      })

    samsung =
      get_or_seed_counterparty!(bytecraft.id, %{
        type: :company,
        tax_id: "12312312",
        full_name: "Samsung",
        display_name: "Samsung",
        address: "Huwaeng 12321/321\nSeoul",
        country: "KR",
        email: "billing@samsung.example",
        phone: "+82 2 555 0101",
        description: "Koreański kontrahent testowy do scenariuszy dopasowywania po znormalizowanym NIP/VAT-ID."
      })

    %{ghostpet: ghostpet, flatearth: flatearth, taco: taco, samsung: samsung}
  end

  # ===========================================================================
  # Projects
  # ===========================================================================

  defp seed_projects(bytecraft, users, counterparties) do
    tenant = bytecraft.id

    firmowid = seed_project!(tenant, "Firmowid", nil)
    ghostpet = seed_project!(tenant, "GhostPet", counterparties.ghostpet.id)
    flatmate = seed_project!(tenant, "FlatMate", counterparties.flatearth.id)
    taco = seed_project!(tenant, "TacoOverflow", counterparties.taco.id)

    project_users = %{
      firmowid => [users.kira.id, users.tomek.id],
      ghostpet => [users.tomek.id, users.maren.id],
      flatmate => [users.kira.id, users.sable.id],
      taco => [users.jules.id, users.maren.id, users.tomek.id]
    }

    for {project, user_ids} <- project_users do
      Enum.each(user_ids, fn user_id ->
        if is_nil(find_project_user(tenant, project.id, user_id)) do
          Ash.Seed.seed!(
            AshProjectUser,
            %{project_id: project.id, user_id: user_id, organization_id: tenant},
            tenant: tenant
          )
        end
      end)
    end

    %{firmowid: firmowid, ghostpet: ghostpet, flatmate: flatmate, taco: taco}
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
  # KSeF credential — test environment token for Bytecraft (NIP 6161525811)
  # ===========================================================================

  @ksef_token "20260405-EC-28297E1000-AA3A3DCEA6-57|nip-6161525811|c8948520f70e428f850a668b445c5ba3579da2cb100d43fbb725d377b3eaa819"

  defp seed_ksef_credential(bytecraft) do
    Ash.Seed.upsert!(
      Credential,
      %{
        organization_id: bytecraft.id,
        status: :working,
        auth_type: :token,
        credentials: @ksef_token
      },
      identity: :unique_organization
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
      institution_id: "ING_PL_INGBPLPW",
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
          institution_id: "BANK_MILLENNIUM_BIGBPLPW",
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

  defp get_or_seed_counterparty!(org_id, attrs) do
    case find_counterparty(org_id, attrs) do
      nil ->
        Ash.Seed.seed!(AshCounterparty, Map.put(attrs, :organization_id, org_id), tenant: org_id)

      counterparty ->
        ensure_counterparty_country!(counterparty, attrs[:country], org_id)
    end
  end

  defp ensure_counterparty_country!(%{country: nil} = counterparty, country, org_id) when is_binary(country) do
    counterparty
    |> Ash.Changeset.for_update(:update, %{country: country}, tenant: org_id, actor: @seed_actor)
    |> Ash.update!()
  end

  defp ensure_counterparty_country!(counterparty, _country, _org_id), do: counterparty

  defp find_counterparty(org_id, attrs) do
    query =
      cond do
        attrs[:tax_id] && attrs[:tax_id] != "" ->
          Ash.Query.filter(
            AshCounterparty,
            tax_id == ^attrs[:tax_id] and organization_id == ^org_id
          )

        attrs[:display_name] ->
          Ash.Query.filter(
            AshCounterparty,
            display_name == ^attrs[:display_name] and organization_id == ^org_id
          )

        true ->
          nil
      end

    case query do
      nil ->
        nil

      query ->
        query = Ash.Query.limit(query, 1)

        case Ash.read(query, tenant: org_id, actor: @seed_actor) do
          {:ok, [counterparty | _]} -> counterparty
          _ -> nil
        end
    end
  end

  defp seed_project!(tenant, name, counterparty_id) do
    tag_definition =
      Ash.Seed.upsert!(
        AshTagDefinition,
        %{name: name, organization_id: tenant},
        identity: :unique_name_per_org,
        tenant: tenant
      )

    project_attrs =
      then(
        %{name: name, organization_id: tenant, tag_definition_id: tag_definition.id},
        fn attrs ->
          if counterparty_id, do: Map.put(attrs, :counterparty_id, counterparty_id), else: attrs
        end
      )

    case find_project(tenant, name) do
      nil -> Ash.Seed.seed!(AshProject, project_attrs, tenant: tenant)
      project -> project
    end
  end

  defp find_project(tenant, name) do
    query =
      AshProject
      |> Ash.Query.filter(organization_id == ^tenant and name == ^name)
      |> Ash.Query.limit(1)

    case Ash.read(query, tenant: tenant, actor: @seed_actor) do
      {:ok, [project | _]} -> project
      _ -> nil
    end
  end

  defp find_project_user(tenant, project_id, user_id) do
    query =
      AshProjectUser
      |> Ash.Query.filter(organization_id == ^tenant and project_id == ^project_id and user_id == ^user_id)
      |> Ash.Query.limit(1)

    case Ash.read(query, tenant: tenant, actor: @seed_actor) do
      {:ok, [project_user | _]} -> project_user
      _ -> nil
    end
  end
end
