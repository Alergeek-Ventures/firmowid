import Ecto.Query

alias Firmowid.Accounts
alias Firmowid.Accounts.Organization
alias Firmowid.BankData.Requisition
alias Firmowid.Blobs
alias Firmowid.CostInvoices
alias Firmowid.Finances
alias Firmowid.Repo
alias Firmowid.SalesInvoices
alias Firmowid.Timetracker

Repo.transaction(fn ->
  alias Firmowid.SalesInvoices.Counterparty

  piotr =
    case Accounts.register_user(%{
           email: "piotr@firmowid.pl",
           password: "kolejka123456"
         }) do
      {:ok, user} -> user
      {:error, _} -> Accounts.get_user_by_email("piotr@firmowid.pl")
    end

  hyzio =
    case Accounts.register_user(%{
           email: "hyzio@firmowid.pl",
           password: "kolejka123456"
         }) do
      {:ok, user} -> user
      {:error, _} -> Accounts.get_user_by_email("hyzio@firmowid.pl")
    end

  Accounts.update_user(piotr, %{
    system_role: :superuser,
    role: :admin,
    name: "Piotr Kowalski",
    employment_date: ~D[2023-01-15],
    phone: "+48 123 456 789",
    slack_id: "U123456789",
    bank_account_number: "12 3456 7890 1234 5678 9012 3456",
    birthday: ~D[1990-05-15],
    position: "Senior Elixir Developer",
    employment_contract_type: :umowa_o_prace,
    student_status_until: nil,
    correspondence_street: "ul. Krakowska 123/45",
    correspondence_city: "Kraków",
    correspondence_code: "30-702",
    residence_street: "ul. Warszawska 67/89",
    residence_city: "Kraków",
    residence_code: "30-001"
  })

  Accounts.update_user(hyzio, %{
    name: "Hyzio Nowak",
    employment_date: ~D[2023-03-20],
    phone: "+48 987 654 321",
    slack_id: "U987654321",
    birthday: ~D[1995-08-22],
    position: "Frontend Developer",
    employment_contract_type: :umowa_zlecenie,
    student_status_until: ~D[2025-06-30],
    correspondence_street: "ul. Gdańska 456/12",
    correspondence_city: "Warszawa",
    correspondence_code: "00-001",
    residence_street: "ul. Poznańska 34/56",
    residence_city: "Warszawa",
    residence_code: "00-002"
  })

  hello_kitty =
    case Repo.one(
           from(o in Organization,
             where: o.nip == "6161525811",
             limit: 1
           ),
           skip_organization_id: true
         ) do
      nil ->
        {:ok, org} =
          Accounts.create_organization(
            %{
              "name" => "Hello Kitty Inc. spółka z ograniczoną odpowiedzialnością",
              "nip" => "6161525811",
              "address" => "Dębowa 5D, 39-994, Kraków",
              "owner_id" => piotr.id
            },
            piotr
          )

        org

      org ->
        org
    end

  Repo.put_org_id(hello_kitty.id)

  case Accounts.create_organization_invites(hello_kitty.id, piotr.id) do
    {:ok, invite} -> Accounts.consume_organization_invite(invite.invite_code, hyzio.id)
    {:error, _} -> :ok
  end

  # Helper to create counterparty only if it doesn't exist (by tax_id or pesel)
  get_or_create_counterparty = fn attrs ->
    existing =
      cond do
        attrs[:tax_id] && attrs[:tax_id] != "" ->
          Repo.one(
            from(c in Counterparty,
              where: c.tax_id == ^attrs[:tax_id] and c.organization_id == ^hello_kitty.id,
              limit: 1
            )
          )

        attrs[:pesel] ->
          Repo.one(
            from(c in Counterparty,
              where: c.pesel == ^attrs[:pesel] and c.organization_id == ^hello_kitty.id,
              limit: 1
            )
          )

        true ->
          nil
      end

    case existing do
      nil -> SalesInvoices.create_counterparty(attrs)
      counterparty -> {:ok, counterparty}
    end
  end

  get_or_create_counterparty.(%{
    type: :company,
    tax_id: "5272830422",
    display_name: "Acme Corporation Sp. z o.o.",
    name: "Jan",
    surname: "Kowalski",
    address: "ul. Testowa 42\n00-001 Warszawa",
    country: "PL",
    email: "kontakt@acme.pl",
    phone: "+48 22 123 45 67",
    description: "Główny klient - usługi programistyczne"
  })

  get_or_create_counterparty.(%{
    type: :company,
    tax_id: "DE123456789",
    display_name: "Deutsche Tech GmbH",
    name: "Hans",
    surname: "Müller",
    address: "Hauptstraße 123\n10115 Berlin",
    country: "DE",
    email: "info@deutsche-tech.de",
    phone: "+49 30 123 456",
    description: "Partner z Niemiec - reverse charge"
  })

  get_or_create_counterparty.(%{
    type: :company,
    tax_id: "US-EIN-12-3456789",
    display_name: "Silicon Valley Inc.",
    name: "John",
    surname: "Smith",
    address: "1 Infinite Loop\nCupertino, CA 95014",
    country: "US",
    email: "billing@svalley.com",
    phone: "+1 408 555 1234",
    description: "Klient z USA - faktura w USD"
  })

  get_or_create_counterparty.(%{
    type: :individual,
    display_name: "Anna Nowak",
    name: "Anna",
    surname: "Nowak",
    pesel: "85010112345",
    address: "ul. Kwiatowa 15/3\n30-001 Kraków",
    country: "PL",
    email: "anna.nowak@email.pl",
    phone: "+48 500 123 456",
    description: "Osoba prywatna - usługi konsultingowe"
  })

  get_or_create_project = fn name ->
    case Timetracker.create_project(%{name: name}) do
      {:ok, project} ->
        project

      {:error, _} ->
        import Ecto.Query

        Repo.one!(
          from p in Firmowid.Timetracker.Project,
            where: p.name == ^name and p.organization_id == ^hello_kitty.id,
            limit: 1
        )
    end
  end

  firmowid = get_or_create_project.("Firmowid")
  hepa = get_or_create_project.("Hepa")
  startapp = get_or_create_project.("Startapp")

  Timetracker.add_user_to_project(piotr.id, firmowid.id)
  Timetracker.add_user_to_project(hyzio.id, firmowid.id)
  Timetracker.add_user_to_project(hyzio.id, hepa.id)
  Timetracker.add_user_to_project(hyzio.id, startapp.id)

  blob =
    case Repo.get(Blobs.Blob, "4ff0d0b1-3298-4b80-9d53-a71d0efc4cad") do
      nil ->
        Repo.insert!(%Blobs.Blob{
          id: "4ff0d0b1-3298-4b80-9d53-a71d0efc4cad",
          blob_path: "4ff0d0b1-3298-4b80-9d53-a71d0efc4cad/01957157-6ba5-7fb9-85cc-6fdbb7fbf181.pdf",
          blob_checksum: "ff2c9062d9a8189522a59805210ebe5d2211e5868d724a47863a0b740d6892b6",
          original_filename: "mobilevikings-2025-03.pdf",
          organization_id: hello_kitty.id
        })

      existing ->
        existing
    end

  mock_requisition =
    Repo.get(Requisition, "b42a914c-d658-46bb-ab4c-950967fbebe1") ||
      Repo.insert!(%Requisition{
        id: "b42a914c-d658-46bb-ab4c-950967fbebe1",
        status: :accepted,
        organization_id: hello_kitty.id
      })

  bank_account =
    Repo.get(Finances.BankAccount, "5e99d40d-8bcb-4088-b6a1-08950daa5ec2") ||
      Repo.insert!(%Finances.BankAccount{
        id: "5e99d40d-8bcb-4088-b6a1-08950daa5ec2",
        iban: "PL58253000082079847123980045",
        institution_id: "NEST_BANK_CORPORATE_PL",
        institution_name: "Nest Bank Corporate",
        owner_name: "Hello Kitty Inc.",
        gocardless_id: "c5831186-ca3e-4edc-a4f5-a48b1d1ead51",
        currency: "PLN",
        organization_id: hello_kitty.id,
        is_default: true,
        requisition_id: mock_requisition.id
      })

  for {id, transaction_id, internal_transaction_id, amount, booking_date, value_date, remittance, inserted_at, updated_at} <-
        [
          {"1f106c75-fb3b-45ba-a876-78c9eab8dd46", "AT#558247778", "a7ba3c4f5cb22887c1b24d91090854a1", -25.00,
           ~D[2025-02-09], ~D[2025-02-06], "Nr karty  ...9285 25,00PLN", ~N[2025-02-10 11:01:08],
           ~N[2025-04-29 11:01:37]},
          {"3254345b-d0e0-4ab3-a1b0-94c1114e6487", "AT#558247777", "2b1fd5fb1fe7007e1d097ab7797243ea", -16.00,
           ~D[2025-02-09], ~D[2025-02-06], "Nr karty  ...9285 16,00PLN", ~N[2025-02-10 11:01:08],
           ~N[2025-04-29 11:01:37]},
          {"00f8897f-604b-4a01-a050-d40fa38dee9f", "AT#558562705", "4401bbdb885cbd5d77ac9e7b55419226", -50.00,
           ~D[2025-02-10], ~D[2025-02-07], "Nr karty  ...9285 50,00PLN", ~N[2025-02-14 11:00:39],
           ~N[2025-04-29 11:01:37]},
          {"2456e77a-879b-434e-a1a6-481f8afc95ba", "AT#559040150", "1cd5cc42967f946b1f6c1b052bca0cbd", -10.00,
           ~D[2025-02-12], ~D[2025-02-09], "Nr karty  ...9285 10,00PLN", ~N[2025-02-14 11:00:39],
           ~N[2025-05-12 11:00:33]},
          {"bddc309c-85b2-41cb-b550-53343797c8b3", "AT#561164105", "58b45609e06837602f718c5787d26529", -25.00,
           ~D[2025-02-22], ~D[2025-02-19], "Nr karty  ...9285 25,00PLN", ~N[2025-02-24 11:00:52], ~N[2025-05-20 11:00:37]}
        ] do
    if is_nil(Repo.get(Finances.Transaction, id)) do
      Repo.insert!(%Finances.Transaction{
        id: id,
        transaction_id: transaction_id,
        internal_transaction_id: internal_transaction_id,
        creditor_name: "www.mobileviking.pl Wroclaw",
        creditor_account: "N/A",
        debtor_name: "ALERGEEK VENTURES SPÓŁKA Z OG",
        debtor_account: "N/A",
        transaction_amount: amount,
        transaction_currency: "PLN",
        booking_date: booking_date,
        value_date: value_date,
        remittance_information_unstructured: remittance,
        skip_invoicing: false,
        bank_account_id: bank_account.id,
        organization_id: hello_kitty.id,
        inserted_at: DateTime.from_naive!(inserted_at, "Etc/UTC"),
        updated_at: DateTime.from_naive!(updated_at, "Etc/UTC")
      })
    end
  end

  if is_nil(Repo.get(CostInvoices.CostInvoice, "01957157-c00d-7433-bd41-3d8b719610a4")) do
    Repo.insert!(%CostInvoices.CostInvoice{
      id: "01957157-c00d-7433-bd41-3d8b719610a4",
      blob_id: blob.id,
      seller: "VikingCo Poland Sp. Z 0.0.",
      seller_display_name: "Mobile Vikings",
      sale_date: ~D[2025-02-28],
      issue_date: ~D[2025-03-05],
      due_date: ~D[2025-03-05],
      total_amount: -126.00,
      currency: "PLN",
      invoice_identifier: "2025-03-0040951-Z",
      description: "Usługi telekomunikacyjne: doładowania na różnych kwotach i pojemności.",
      skip_invoicing: false,
      organization_id: hello_kitty.id,
      seller_address: "plac Grunwaldzki 23, 50-365 Wroclaw"
    })
  end

  transactions = [
    %{
      internal_transaction_id: "txn_001",
      debtor_name: "Acme Corporation",
      creditor_name: "Hello Kitty Inc.",
      remittance_information_unstructured: "Invoice #INV-2024-001 for software development services",
      transaction_currency: "USD",
      transaction_amount: 5000.00,
      booking_date: Date.utc_today(),
      organization_id: hello_kitty.id
    },
    %{
      internal_transaction_id: "txn_002",
      debtor_name: "Beta Solutions LLC",
      creditor_name: "Hello Kitty Inc.",
      remittance_information_unstructured: "Monthly subscription payment for SaaS platform",
      transaction_currency: "EUR",
      transaction_amount: 299.99,
      booking_date: Date.utc_today(),
      organization_id: hello_kitty.id
    },
    %{
      internal_transaction_id: "txn_003",
      debtor_name: "Gamma Technologies",
      creditor_name: "Hello Kitty Inc.",
      remittance_information_unstructured: "Consulting fee for Q1 2024 project",
      transaction_currency: "PLN",
      transaction_amount: 15_000.00,
      booking_date: Date.utc_today(),
      organization_id: hello_kitty.id
    },
    %{
      internal_transaction_id: "txn_004",
      debtor_name: "Hello Kitty Inc.",
      creditor_name: "Delta Hosting Services",
      remittance_information_unstructured: "Cloud hosting payment for January 2024",
      transaction_currency: "USD",
      transaction_amount: 250.00,
      booking_date: Date.utc_today(),
      organization_id: hello_kitty.id
    },
    %{
      internal_transaction_id: "txn_005",
      debtor_name: "Epsilon Marketing",
      creditor_name: "Hello Kitty Inc.",
      remittance_information_unstructured: "Digital marketing campaign Q1 2024",
      transaction_currency: "EUR",
      transaction_amount: 1200.00,
      booking_date: Date.utc_today(),
      organization_id: hello_kitty.id
    },
    %{
      internal_transaction_id: "txn_006",
      debtor_name: "Zeta Consulting Group",
      creditor_name: "Hello Kitty Inc.",
      remittance_information_unstructured: "Payment for design sprint facilitation",
      transaction_currency: "USD",
      transaction_amount: 3500.00,
      booking_date: Date.utc_today(),
      organization_id: hello_kitty.id
    },
    %{
      internal_transaction_id: "txn_007",
      debtor_name: "Hello Kitty Inc.",
      creditor_name: "Omega Legal Services",
      remittance_information_unstructured: "Legal retainer fee for 2024 Q1",
      transaction_currency: "EUR",
      transaction_amount: 2000.00,
      booking_date: Date.utc_today(),
      organization_id: hello_kitty.id
    },
    %{
      internal_transaction_id: "txn_008",
      debtor_name: "Theta Electronics",
      creditor_name: "Hello Kitty Inc.",
      remittance_information_unstructured: "Hardware procurement invoice INV-2024-045",
      transaction_currency: "USD",
      transaction_amount: 8900.00,
      booking_date: Date.utc_today(),
      organization_id: hello_kitty.id
    },
    %{
      internal_transaction_id: "txn_009",
      debtor_name: "Hello Kitty Inc.",
      creditor_name: "Lambda Insurance Co.",
      remittance_information_unstructured: "Annual corporate insurance premium",
      transaction_currency: "USD",
      transaction_amount: 4200.00,
      booking_date: Date.utc_today(),
      organization_id: hello_kitty.id
    },
    %{
      internal_transaction_id: "txn_010",
      debtor_name: "Sigma Logistics",
      creditor_name: "Hello Kitty Inc.",
      remittance_information_unstructured: "Logistics and shipping fees for February",
      transaction_currency: "GBP",
      transaction_amount: 1800.50,
      booking_date: Date.utc_today(),
      organization_id: hello_kitty.id
    },
    %{
      internal_transaction_id: "txn_011",
      debtor_name: "Hello Kitty Inc.",
      creditor_name: "Alpha Data Analytics",
      remittance_information_unstructured: "Data analytics consulting project payment",
      transaction_currency: "USD",
      transaction_amount: 6400.00,
      booking_date: Date.utc_today(),
      organization_id: hello_kitty.id
    },
    %{
      internal_transaction_id: "txn_012",
      debtor_name: "Omicron Retailers Ltd.",
      creditor_name: "Hello Kitty Inc.",
      remittance_information_unstructured: "Invoice INV-2024-078 for retail software integration",
      transaction_currency: "CAD",
      transaction_amount: 7200.00,
      booking_date: Date.utc_today(),
      organization_id: hello_kitty.id
    },
    %{
      internal_transaction_id: "txn_013",
      debtor_name: "Hello Kitty Inc.",
      creditor_name: "NuPrint Office Supplies",
      remittance_information_unstructured: "Office supplies order #5678",
      transaction_currency: "USD",
      transaction_amount: 480.75,
      booking_date: Date.utc_today(),
      organization_id: hello_kitty.id
    },
    %{
      internal_transaction_id: "txn_014",
      debtor_name: "Psi Media Agency",
      creditor_name: "Hello Kitty Inc.",
      remittance_information_unstructured: "Advertising campaign for March 2024",
      transaction_currency: "EUR",
      transaction_amount: 2600.00,
      booking_date: Date.utc_today(),
      organization_id: hello_kitty.id
    },
    %{
      internal_transaction_id: "txn_015",
      debtor_name: "Hello Kitty Inc.",
      creditor_name: "Rho Coworking Spaces",
      remittance_information_unstructured: "Coworking space rental fee - April 2024",
      transaction_currency: "USD",
      transaction_amount: 950.00,
      booking_date: Date.utc_today(),
      organization_id: hello_kitty.id
    },
    %{
      internal_transaction_id: "txn_016",
      debtor_name: "Delta Hosting Services",
      creditor_name: "Hello Kitty Inc.",
      remittance_information_unstructured: "Refund for overpayment in January",
      transaction_currency: "USD",
      transaction_amount: -50.00,
      booking_date: Date.utc_today(),
      organization_id: hello_kitty.id
    },
    %{
      internal_transaction_id: "txn_017",
      debtor_name: "Kappa Manufacturing",
      creditor_name: "Hello Kitty Inc.",
      remittance_information_unstructured: "Invoice INV-2024-112 for industrial automation software",
      transaction_currency: "JPY",
      transaction_amount: 650_000.00,
      booking_date: Date.utc_today(),
      organization_id: hello_kitty.id
    },
    %{
      internal_transaction_id: "txn_018",
      debtor_name: "Hello Kitty Inc.",
      creditor_name: "Tau Energy Solutions",
      remittance_information_unstructured: "Electricity bill for March 2024",
      transaction_currency: "USD",
      transaction_amount: 320.45,
      booking_date: Date.utc_today(),
      organization_id: hello_kitty.id
    },
    %{
      internal_transaction_id: "txn_019",
      debtor_name: "Upsilon Finance Ltd.",
      creditor_name: "Hello Kitty Inc.",
      remittance_information_unstructured: "Financial audit service for FY2023",
      transaction_currency: "GBP",
      transaction_amount: 5100.00,
      booking_date: Date.utc_today(),
      organization_id: hello_kitty.id
    },
    %{
      internal_transaction_id: "txn_020",
      debtor_name: "Hello Kitty Inc.",
      creditor_name: "Zeta Consulting Group",
      remittance_information_unstructured: "Payment for strategic partnership workshop",
      transaction_currency: "EUR",
      transaction_amount: 2750.00,
      booking_date: Date.utc_today(),
      organization_id: hello_kitty.id
    },
    %{
      internal_transaction_id: "txn_021",
      debtor_name: "Lambda Insurance Co.",
      creditor_name: "Hello Kitty Inc.",
      remittance_information_unstructured: "Claim payout for policy #POL-2024-005",
      transaction_currency: "USD",
      transaction_amount: 1500.00,
      booking_date: Date.utc_today(),
      organization_id: hello_kitty.id
    },
    %{
      internal_transaction_id: "txn_022",
      debtor_name: "Hello Kitty Inc.",
      creditor_name: "Epsilon Marketing",
      remittance_information_unstructured: "Marketing retainer fee for April 2024",
      transaction_currency: "EUR",
      transaction_amount: 1200.00,
      booking_date: Date.utc_today(),
      organization_id: hello_kitty.id
    },
    %{
      internal_transaction_id: "txn_023",
      debtor_name: "Beta Solutions LLC",
      creditor_name: "Hello Kitty Inc.",
      remittance_information_unstructured: "Payment for Q2 SaaS subscription",
      transaction_currency: "EUR",
      transaction_amount: 299.99,
      booking_date: Date.utc_today(),
      organization_id: hello_kitty.id
    },
    %{
      internal_transaction_id: "txn_024",
      debtor_name: "Hello Kitty Inc.",
      creditor_name: "Sigma Logistics",
      remittance_information_unstructured: "April 2024 freight and transport services",
      transaction_currency: "GBP",
      transaction_amount: 1900.00,
      booking_date: Date.utc_today(),
      organization_id: hello_kitty.id
    },
    %{
      internal_transaction_id: "txn_025",
      debtor_name: "Theta Electronics",
      creditor_name: "Hello Kitty Inc.",
      remittance_information_unstructured: "Final installment for hardware integration project",
      transaction_currency: "USD",
      transaction_amount: 4500.00,
      booking_date: Date.utc_today(),
      organization_id: hello_kitty.id
    }
  ]

  Finances.create_or_update_transactions(transactions)

  existing_invoice =
    Repo.one(
      from(si in SalesInvoices.SalesInvoice,
        where: si.invoice_number == "FV/2025/11/001" and si.organization_id == ^hello_kitty.id,
        limit: 1
      )
    )

  if is_nil(existing_invoice) do
    SalesInvoices.create_sales_invoice(
      %SalesInvoices.SalesInvoice{organization_id: hello_kitty.id},
      %{
        "id" => "019d0001-0000-7000-8000-000000000001",
        "invoice_number" => "FV/2025/11/001",
        "invoice_type" => "poland",
        "issue_date" => ~D[2025-11-15],
        "sale_date" => ~D[2025-11-15],
        "due_date" => ~D[2025-11-29],
        "currency" => "PLN",
        "seller_display_name" => "Hello Kitty Inc.",
        "seller_address" => "Lipowa 3D, 30-702, Kraków",
        "seller_nip" => "6161525811",
        "seller_account_number" => "PL58253000082079847123980045",
        "buyer_display_name" => "Acme Corporation Sp. z o.o.",
        "buyer_full_name" => "Acme Corporation Sp. z o.o.",
        "buyer_address" => "ul. Testowa 42, 00-001 Warszawa",
        "buyer_country" => "PL",
        "buyer_id" => "9876543210",
        "buyer_type" => "company",
        "payment_method" => "transfer",
        "is_reverse_charge" => false,
        "is_cash_account" => false,
        "sales_invoice_items" => [
          %{
            "name" => "Usługi programistyczne - aplikacja webowa",
            "quantity" => 40,
            "unit" => "godz.",
            "unit_price" => 250.00,
            "vat_rate" => "23"
          },
          %{
            "name" => "Konsultacje techniczne",
            "quantity" => 8,
            "unit" => "godz.",
            "unit_price" => 300.00,
            "vat_rate" => "23"
          },
          %{
            "name" => "Hosting i utrzymanie serwera",
            "quantity" => 1,
            "unit" => "m-c",
            "unit_price" => 500.00,
            "vat_rate" => "23"
          }
        ]
      }
    )
  end

  ksef_success_invoice =
    Repo.one(
      from(si in SalesInvoices.SalesInvoice,
        where: si.invoice_number == "01/01/2025" and si.organization_id == ^hello_kitty.id,
        limit: 1
      )
    )

  if is_nil(ksef_success_invoice) do
    {:ok, invoice} =
      SalesInvoices.create_sales_invoice(
        %SalesInvoices.SalesInvoice{organization_id: hello_kitty.id},
        %{
          "invoice_number" => "01/01/2025",
          "invoice_type" => "poland",
          "issue_date" => ~D[2025-01-10],
          "sale_date" => ~D[2025-01-10],
          "due_date" => ~D[2025-01-24],
          "currency" => "PLN",
          "seller_display_name" => "Hello Kitty Inc.",
          "seller_address" => "Lipowa 3D, 30-702, Kraków",
          "seller_nip" => "6161525811",
          "seller_account_number" => "PL58253000082079847123980045",
          "buyer_display_name" => "KSeF Test Client Sp. z o.o.",
          "buyer_full_name" => "KSeF Test Client Sp. z o.o.",
          "buyer_address" => "ul. Sukcesu 1, 00-001 Warszawa",
          "buyer_country" => "PL",
          "buyer_id" => "1111111111",
          "buyer_type" => "company",
          "payment_method" => "transfer",
          "is_reverse_charge" => false,
          "is_cash_account" => false,
          "sales_invoice_items" => [
            %{
              "name" => "Usługi konsultingowe",
              "quantity" => 10,
              "unit" => "godz.",
              "unit_price" => 200.00,
              "vat_rate" => "23"
            }
          ]
        }
      )

    invoice
    |> Ecto.Changeset.change(%{
      ksef_number: "1111111111-20250110-ABC123DEF456-00",
      ksef_session_reference_number: "20250110-SE-ABC123DEF456-00",
      locked_at: ~U[2025-01-10 12:00:00Z]
    })
    |> Repo.update!()
  end

  ksef_sending_invoice =
    Repo.one(
      from(si in SalesInvoices.SalesInvoice,
        where: si.invoice_number == "02/01/2025" and si.organization_id == ^hello_kitty.id,
        limit: 1
      )
    )

  if is_nil(ksef_sending_invoice) do
    {:ok, invoice} =
      SalesInvoices.create_sales_invoice(
        %SalesInvoices.SalesInvoice{organization_id: hello_kitty.id},
        %{
          "invoice_number" => "02/01/2025",
          "invoice_type" => "poland",
          "issue_date" => ~D[2025-01-15],
          "sale_date" => ~D[2025-01-15],
          "due_date" => ~D[2025-01-29],
          "currency" => "PLN",
          "seller_display_name" => "Hello Kitty Inc.",
          "seller_address" => "Lipowa 3D, 30-702, Kraków",
          "seller_nip" => "6161525811",
          "seller_account_number" => "PL58253000082079847123980045",
          "buyer_display_name" => "Wysyłka Test Sp. z o.o.",
          "buyer_full_name" => "Wysyłka Test Sp. z o.o.",
          "buyer_address" => "ul. Kolejki 2, 00-002 Warszawa",
          "buyer_country" => "PL",
          "buyer_id" => "2222222222",
          "buyer_type" => "company",
          "payment_method" => "transfer",
          "is_reverse_charge" => false,
          "is_cash_account" => false,
          "sales_invoice_items" => [
            %{
              "name" => "Usługi w trakcie wysyłki do KSeF",
              "quantity" => 5,
              "unit" => "godz.",
              "unit_price" => 150.00,
              "vat_rate" => "23"
            }
          ]
        }
      )

    invoice
    |> Ecto.Changeset.change(%{
      ksef_number: nil,
      ksef_session_reference_number: "20250115-SE-SENDING123-00",
      locked_at: ~U[2025-01-15 10:00:00Z]
    })
    |> Repo.update!()

    Repo.query!(
      """
      INSERT INTO oban.oban_jobs (state, queue, worker, args, attempt, max_attempts, inserted_at, scheduled_at, attempted_at, priority, tags, meta)
      VALUES ('executing', 'ksef_submissions', 'Firmowid.Ksef.SubmissionWorker',
              $1::jsonb, 1, 3, NOW(), NOW(), NOW(), 0, ARRAY[]::text[], $2::jsonb)
      ON CONFLICT DO NOTHING
      """,
      [
        %{
          "action" => "verify",
          "organization_id" => hello_kitty.id,
          "sales_invoice_id" => invoice.id,
          "session_reference" => "20250115-SE-SENDING123-00",
          "invoice_reference" => "INV-REF-SENDING-001"
        },
        %{"organization_id" => hello_kitty.id}
      ]
    )
  end

  ksef_failed_invoice =
    Repo.one(
      from(si in SalesInvoices.SalesInvoice,
        where: si.invoice_number == "03/01/2025" and si.organization_id == ^hello_kitty.id,
        limit: 1
      )
    )

  if is_nil(ksef_failed_invoice) do
    {:ok, invoice} =
      SalesInvoices.create_sales_invoice(
        %SalesInvoices.SalesInvoice{organization_id: hello_kitty.id},
        %{
          "invoice_number" => "03/01/2025",
          "invoice_type" => "poland",
          "issue_date" => ~D[2025-01-20],
          "sale_date" => ~D[2025-01-20],
          "due_date" => ~D[2025-02-03],
          "currency" => "PLN",
          "seller_display_name" => "Hello Kitty Inc.",
          "seller_address" => "Lipowa 3D, 30-702, Kraków",
          "seller_nip" => "6161525811",
          "seller_account_number" => "PL58253000082079847123980045",
          "buyer_display_name" => "Błąd Test Sp. z o.o.",
          "buyer_full_name" => "Błąd Test Sp. z o.o.",
          "buyer_address" => "ul. Awarii 3, 00-003 Warszawa",
          "buyer_country" => "PL",
          "buyer_id" => "3333333333",
          "buyer_type" => "company",
          "payment_method" => "transfer",
          "is_reverse_charge" => false,
          "is_cash_account" => false,
          "sales_invoice_items" => [
            %{
              "name" => "Usługi - błąd wysyłki KSeF",
              "quantity" => 3,
              "unit" => "godz.",
              "unit_price" => 100.00,
              "vat_rate" => "23"
            }
          ]
        }
      )

    invoice
    |> Ecto.Changeset.change(%{
      ksef_number: nil,
      ksef_session_reference_number: "20250120-SE-FAILED456-00",
      locked_at: ~U[2025-01-20 14:00:00Z]
    })
    |> Repo.update!()

    Repo.query!(
      """
      INSERT INTO oban.oban_jobs (state, queue, worker, args, attempt, max_attempts, inserted_at, scheduled_at, discarded_at, priority, tags, meta, errors)
      VALUES ('discarded', 'ksef_submissions', 'Firmowid.Ksef.SubmissionWorker',
              $1::jsonb, 3, 3, NOW() - INTERVAL '1 hour', NOW() - INTERVAL '1 hour', NOW(), 0, ARRAY[]::text[], $2::jsonb,
              ARRAY[
                '{"at": "2025-01-20T14:05:00Z", "attempt": 1, "error": "KSeF API error: connection timeout"}',
                '{"at": "2025-01-20T14:10:00Z", "attempt": 2, "error": "KSeF API error: connection timeout"}',
                '{"at": "2025-01-20T14:15:00Z", "attempt": 3, "error": "KSeF API error: connection timeout"}'
              ]::jsonb[])
      ON CONFLICT DO NOTHING
      """,
      [
        %{
          "action" => "verify",
          "organization_id" => hello_kitty.id,
          "sales_invoice_id" => invoice.id,
          "session_reference" => "20250120-SE-FAILED456-00",
          "invoice_reference" => "INV-REF-FAILED-001"
        },
        %{"organization_id" => hello_kitty.id}
      ]
    )
  end

  evil_user =
    case Accounts.register_user(%{
           email: "evil@competitor.com",
           password: "kolejka123456"
         }) do
      {:ok, user} -> user
      {:error, _} -> Accounts.get_user_by_email("evil@competitor.com")
    end

  Accounts.update_user(evil_user, %{system_role: :user, role: :admin})

  evil_org =
    case Repo.one(
           from(o in Organization,
             where: o.nip == "9999999999",
             limit: 1
           ),
           skip_organization_id: true
         ) do
      nil ->
        {:ok, org} =
          Accounts.create_organization(
            %{
              "name" => "Evil Competitor Corp",
              "nip" => "9999999999",
              "address" => "Dark Street 666, 00-666, Warszawa",
              "owner_id" => evil_user.id
            },
            evil_user
          )

        org

      org ->
        org
    end

  Repo.put_org_id(evil_org.id)

  evil_project = get_or_create_project.("Evil Project")
  Timetracker.add_user_to_project(evil_user.id, evil_project.id)

  evil_blob =
    case Repo.get(Blobs.Blob, "aaaaaaaa-1111-4b80-9d53-a71d0efc4cad") do
      nil ->
        Repo.insert!(%Blobs.Blob{
          id: "aaaaaaaa-1111-4b80-9d53-a71d0efc4cad",
          blob_path: "aaaaaaaa-1111-4b80-9d53-a71d0efc4cad/evil-invoice.pdf",
          blob_checksum: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          original_filename: "evil-secret-invoice.pdf",
          organization_id: evil_org.id
        })

      existing ->
        existing
    end

  if is_nil(Repo.get(CostInvoices.CostInvoice, "aaaaaaaa-2222-7433-bd41-3d8b719610a4")) do
    Repo.insert!(%CostInvoices.CostInvoice{
      id: "aaaaaaaa-2222-7433-bd41-3d8b719610a4",
      blob_id: evil_blob.id,
      seller: "Super Secret Supplier Inc.",
      seller_display_name: "Secret Supplier",
      sale_date: ~D[2025-11-18],
      issue_date: ~D[2025-11-19],
      due_date: ~D[2025-12-19],
      total_amount: -99_999.99,
      currency: "PLN",
      invoice_identifier: "SECRET/2025/11/666",
      description: "Top secret confidential services - DO NOT SHARE",
      skip_invoicing: false,
      organization_id: evil_org.id,
      seller_address: "Confidential Address 1, Secret Location"
    })
  end

  existing_evil_invoice =
    Repo.one(
      from(si in SalesInvoices.SalesInvoice,
        where: si.invoice_number == "EVIL/2025/11/001" and si.organization_id == ^evil_org.id,
        limit: 1
      )
    )

  if is_nil(existing_evil_invoice) do
    SalesInvoices.create_sales_invoice(
      %SalesInvoices.SalesInvoice{organization_id: evil_org.id},
      %{
        "id" => "aaaaaaaa-3333-7000-8000-000000000001",
        "invoice_number" => "EVIL/2025/11/001",
        "invoice_type" => "poland",
        "issue_date" => ~D[2025-11-20],
        "sale_date" => ~D[2025-11-20],
        "due_date" => ~D[2025-12-04],
        "currency" => "PLN",
        "seller_display_name" => "Evil Competitor Corp",
        "seller_address" => "Dark Street 666, 00-666, Warszawa",
        "seller_nip" => "9999999999",
        "seller_account_number" => "PL99999999999999999999999999",
        "buyer_display_name" => "Confidential Client Sp. z o.o.",
        "buyer_full_name" => "Confidential Client Sp. z o.o.",
        "buyer_address" => "ul. Tajna 13, 00-666 Warszawa",
        "buyer_country" => "PL",
        "buyer_id" => "6666666666",
        "buyer_type" => "company",
        "payment_method" => "transfer",
        "is_reverse_charge" => false,
        "is_cash_account" => false,
        "sales_invoice_items" => [
          %{
            "name" => "Highly confidential consulting services",
            "quantity" => 100,
            "unit" => "godz.",
            "unit_price" => 1000.00,
            "vat_rate" => "23"
          },
          %{
            "name" => "Secret proprietary software license",
            "quantity" => 1,
            "unit" => "szt.",
            "unit_price" => 50_000.00,
            "vat_rate" => "23"
          }
        ]
      }
    )
  end

  IO.puts("""
  KSeF Test Environment
  =====================
  To test invoice submission to KSeF, generate an authorization token:

  URL: https://ap-test.ksef.mf.gov.pl/web/tokens/generate-token
  NIP: 6161525811 (Hello Kitty Inc.)

  This is the TEST environment (ap-test.ksef.mf.gov.pl).
  App in development and local environments is already set up to use it.


  Production uses: ksef.mf.gov.pl - you can connect to it if you modify
  configuration in config/config.exs.
  """)
end)
