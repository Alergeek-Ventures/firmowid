import Ecto.Query

alias Firmowid.Accounts
alias Firmowid.Accounts.Organization
alias Firmowid.Analysis
alias Firmowid.BankData.Requisition
alias Firmowid.Blobs
alias Firmowid.CostInvoices
alias Firmowid.Finances
alias Firmowid.Repo
alias Firmowid.SalesInvoices
alias Firmowid.Timetracker

# ---------------------------------------------------------------------------
# Date helpers — all seed dates are relative to today so the dashboard
# always shows data in the current month and the two preceding months.
# ---------------------------------------------------------------------------
today = Date.utc_today()

# Returns a date in the current month clamped to the last day if needed.
date_this_month = fn day ->
  Date.new!(today.year, today.month, min(day, Date.days_in_month(today)))
end

months_ago = fn months ->
  Date.shift(today, month: -months)
end

# Returns a date N months ago, on the given day (clamped).
date_months_ago = fn months, day ->
  ref = months_ago.(months)
  Date.new!(ref.year, ref.month, min(day, Date.days_in_month(ref)))
end

Repo.transaction(fn ->
  alias Firmowid.SalesInvoices.Counterparty
  alias Firmowid.Timetracker.ProjectUser

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
    case Repo.one(
           from(p in Firmowid.Timetracker.Project,
             where: p.name == ^name and p.organization_id == ^hello_kitty.id,
             limit: 1
           )
         ) do
      nil ->
        {:ok, project} = Timetracker.create_project(%{name: name})
        project

      project ->
        project
    end
  end

  firmowid = get_or_create_project.("Firmowid")
  hepa = get_or_create_project.("Hepa")
  startapp = get_or_create_project.("Startapp")

  for {user_id, project_id} <- [
        {piotr.id, firmowid.id},
        {hyzio.id, firmowid.id},
        {hyzio.id, hepa.id},
        {hyzio.id, startapp.id}
      ] do
    if !Repo.one(
         from(pu in ProjectUser,
           where: pu.user_id == ^user_id and pu.project_id == ^project_id,
           limit: 1
         )
       ) do
      Timetracker.add_user_to_project(user_id, project_id)
    end
  end

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

  # ---------------------------------------------------------------------------
  # Current month — Mobile Vikings card transactions + cost invoice
  # These are *unmatched* transactions showing the raw bank feed state.
  # The cost invoice is also unmatched (no linked transactions).
  # ---------------------------------------------------------------------------

  for {id, transaction_id, internal_transaction_id, amount, day_offset, value_day_offset, remittance} <-
        [
          {"1f106c75-fb3b-45ba-a876-78c9eab8dd46", "AT#558247778", "a7ba3c4f5cb22887c1b24d91090854a1", -25.00, 9, 6,
           "Nr karty  ...9285 25,00PLN"},
          {"3254345b-d0e0-4ab3-a1b0-94c1114e6487", "AT#558247777", "2b1fd5fb1fe7007e1d097ab7797243ea", -16.00, 9, 6,
           "Nr karty  ...9285 16,00PLN"},
          {"00f8897f-604b-4a01-a050-d40fa38dee9f", "AT#558562705", "4401bbdb885cbd5d77ac9e7b55419226", -50.00, 10, 7,
           "Nr karty  ...9285 50,00PLN"},
          {"2456e77a-879b-434e-a1a6-481f8afc95ba", "AT#559040150", "1cd5cc42967f946b1f6c1b052bca0cbd", -10.00, 12, 9,
           "Nr karty  ...9285 10,00PLN"},
          {"bddc309c-85b2-41cb-b550-53343797c8b3", "AT#561164105", "58b45609e06837602f718c5787d26529", -25.00, 5, 3,
           "Nr karty  ...9285 25,00PLN"}
        ] do
    if is_nil(Repo.get(Finances.Transaction, id)) do
      now = DateTime.truncate(DateTime.utc_now(), :second)

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
        booking_date: date_this_month.(day_offset),
        value_date: date_this_month.(value_day_offset),
        remittance_information_unstructured: remittance,
        skip_invoicing: false,
        bank_account_id: bank_account.id,
        organization_id: hello_kitty.id,
        inserted_at: now,
        updated_at: now
      })
    end
  end

  if is_nil(Repo.get(CostInvoices.CostInvoice, "01957157-c00d-7433-bd41-3d8b719610a4")) do
    Repo.insert!(%CostInvoices.CostInvoice{
      id: "01957157-c00d-7433-bd41-3d8b719610a4",
      blob_id: blob.id,
      seller: "VikingCo Poland Sp. Z 0.0.",
      seller_display_name: "Mobile Vikings",
      sale_date: date_this_month.(1),
      issue_date: date_this_month.(5),
      due_date: date_this_month.(5),
      total_amount: -126.00,
      currency: "PLN",
      invoice_identifier: "#{today.year}-#{String.pad_leading("#{today.month}", 2, "0")}-0040951-Z",
      description: "Usługi telekomunikacyjne: doładowania na różnych kwotach i pojemności.",
      skip_invoicing: false,
      organization_id: hello_kitty.id,
      seller_address: "plac Grunwaldzki 23, 50-365 Wroclaw"
    })
  end

  # Current-month unmatched bank transactions (no bank_account — simulating API feed)
  transactions = [
    %{
      internal_transaction_id: "txn_001",
      debtor_name: "Acme Corporation",
      creditor_name: "Hello Kitty Inc.",
      remittance_information_unstructured: "Invoice #INV-2024-001 for software development services",
      transaction_currency: "USD",
      transaction_amount: 5000.00,
      booking_date: date_this_month.(1),
      organization_id: hello_kitty.id
    },
    %{
      internal_transaction_id: "txn_002",
      debtor_name: "Beta Solutions LLC",
      creditor_name: "Hello Kitty Inc.",
      remittance_information_unstructured: "Monthly subscription payment for SaaS platform",
      transaction_currency: "EUR",
      transaction_amount: 299.99,
      booking_date: date_this_month.(2),
      organization_id: hello_kitty.id
    },
    %{
      internal_transaction_id: "txn_003",
      debtor_name: "Gamma Technologies",
      creditor_name: "Hello Kitty Inc.",
      remittance_information_unstructured: "Consulting fee for Q1 2024 project",
      transaction_currency: "PLN",
      transaction_amount: 15_000.00,
      booking_date: date_this_month.(3),
      organization_id: hello_kitty.id
    },
    %{
      internal_transaction_id: "txn_004",
      debtor_name: "Hello Kitty Inc.",
      creditor_name: "Delta Hosting Services",
      remittance_information_unstructured: "Cloud hosting payment for January 2024",
      transaction_currency: "USD",
      transaction_amount: 250.00,
      booking_date: date_this_month.(3),
      organization_id: hello_kitty.id
    },
    %{
      internal_transaction_id: "txn_005",
      debtor_name: "Epsilon Marketing",
      creditor_name: "Hello Kitty Inc.",
      remittance_information_unstructured: "Digital marketing campaign Q1 2024",
      transaction_currency: "EUR",
      transaction_amount: 1200.00,
      booking_date: date_this_month.(4),
      organization_id: hello_kitty.id
    },
    %{
      internal_transaction_id: "txn_006",
      debtor_name: "Zeta Consulting Group",
      creditor_name: "Hello Kitty Inc.",
      remittance_information_unstructured: "Payment for design sprint facilitation",
      transaction_currency: "USD",
      transaction_amount: 3500.00,
      booking_date: date_this_month.(4),
      organization_id: hello_kitty.id
    },
    %{
      internal_transaction_id: "txn_007",
      debtor_name: "Hello Kitty Inc.",
      creditor_name: "Omega Legal Services",
      remittance_information_unstructured: "Legal retainer fee for 2024 Q1",
      transaction_currency: "EUR",
      transaction_amount: 2000.00,
      booking_date: date_this_month.(5),
      organization_id: hello_kitty.id
    },
    %{
      internal_transaction_id: "txn_008",
      debtor_name: "Theta Electronics",
      creditor_name: "Hello Kitty Inc.",
      remittance_information_unstructured: "Hardware procurement invoice INV-2024-045",
      transaction_currency: "USD",
      transaction_amount: 8900.00,
      booking_date: date_this_month.(5),
      organization_id: hello_kitty.id
    },
    %{
      internal_transaction_id: "txn_009",
      debtor_name: "Hello Kitty Inc.",
      creditor_name: "Lambda Insurance Co.",
      remittance_information_unstructured: "Annual corporate insurance premium",
      transaction_currency: "USD",
      transaction_amount: 4200.00,
      booking_date: date_this_month.(6),
      organization_id: hello_kitty.id
    },
    %{
      internal_transaction_id: "txn_010",
      debtor_name: "Sigma Logistics",
      creditor_name: "Hello Kitty Inc.",
      remittance_information_unstructured: "Logistics and shipping fees for February",
      transaction_currency: "GBP",
      transaction_amount: 1800.50,
      booking_date: date_this_month.(6),
      organization_id: hello_kitty.id
    },
    %{
      internal_transaction_id: "txn_011",
      debtor_name: "Hello Kitty Inc.",
      creditor_name: "Alpha Data Analytics",
      remittance_information_unstructured: "Data analytics consulting project payment",
      transaction_currency: "USD",
      transaction_amount: 6400.00,
      booking_date: date_this_month.(7),
      organization_id: hello_kitty.id
    },
    %{
      internal_transaction_id: "txn_012",
      debtor_name: "Omicron Retailers Ltd.",
      creditor_name: "Hello Kitty Inc.",
      remittance_information_unstructured: "Invoice INV-2024-078 for retail software integration",
      transaction_currency: "CAD",
      transaction_amount: 7200.00,
      booking_date: date_this_month.(7),
      organization_id: hello_kitty.id
    },
    %{
      internal_transaction_id: "txn_013",
      debtor_name: "Hello Kitty Inc.",
      creditor_name: "NuPrint Office Supplies",
      remittance_information_unstructured: "Office supplies order #5678",
      transaction_currency: "USD",
      transaction_amount: 480.75,
      booking_date: date_this_month.(8),
      organization_id: hello_kitty.id
    },
    %{
      internal_transaction_id: "txn_014",
      debtor_name: "Psi Media Agency",
      creditor_name: "Hello Kitty Inc.",
      remittance_information_unstructured: "Advertising campaign for March 2024",
      transaction_currency: "EUR",
      transaction_amount: 2600.00,
      booking_date: date_this_month.(8),
      organization_id: hello_kitty.id
    },
    %{
      internal_transaction_id: "txn_015",
      debtor_name: "Hello Kitty Inc.",
      creditor_name: "Rho Coworking Spaces",
      remittance_information_unstructured: "Coworking space rental fee - April 2024",
      transaction_currency: "USD",
      transaction_amount: 950.00,
      booking_date: date_this_month.(9),
      organization_id: hello_kitty.id
    },
    %{
      internal_transaction_id: "txn_016",
      debtor_name: "Delta Hosting Services",
      creditor_name: "Hello Kitty Inc.",
      remittance_information_unstructured: "Refund for overpayment in January",
      transaction_currency: "USD",
      transaction_amount: -50.00,
      booking_date: date_this_month.(9),
      organization_id: hello_kitty.id
    },
    %{
      internal_transaction_id: "txn_017",
      debtor_name: "Kappa Manufacturing",
      creditor_name: "Hello Kitty Inc.",
      remittance_information_unstructured: "Invoice INV-2024-112 for industrial automation software",
      transaction_currency: "JPY",
      transaction_amount: 650_000.00,
      booking_date: date_this_month.(10),
      organization_id: hello_kitty.id
    },
    %{
      internal_transaction_id: "txn_018",
      debtor_name: "Hello Kitty Inc.",
      creditor_name: "Tau Energy Solutions",
      remittance_information_unstructured: "Electricity bill for March 2024",
      transaction_currency: "USD",
      transaction_amount: 320.45,
      booking_date: date_this_month.(10),
      organization_id: hello_kitty.id
    },
    %{
      internal_transaction_id: "txn_019",
      debtor_name: "Upsilon Finance Ltd.",
      creditor_name: "Hello Kitty Inc.",
      remittance_information_unstructured: "Financial audit service for FY2023",
      transaction_currency: "GBP",
      transaction_amount: 5100.00,
      booking_date: date_this_month.(11),
      organization_id: hello_kitty.id
    },
    %{
      internal_transaction_id: "txn_020",
      debtor_name: "Hello Kitty Inc.",
      creditor_name: "Zeta Consulting Group",
      remittance_information_unstructured: "Payment for strategic partnership workshop",
      transaction_currency: "EUR",
      transaction_amount: 2750.00,
      booking_date: date_this_month.(11),
      organization_id: hello_kitty.id
    },
    %{
      internal_transaction_id: "txn_021",
      debtor_name: "Lambda Insurance Co.",
      creditor_name: "Hello Kitty Inc.",
      remittance_information_unstructured: "Claim payout for policy #POL-2024-005",
      transaction_currency: "USD",
      transaction_amount: 1500.00,
      booking_date: date_this_month.(12),
      organization_id: hello_kitty.id
    },
    %{
      internal_transaction_id: "txn_022",
      debtor_name: "Hello Kitty Inc.",
      creditor_name: "Epsilon Marketing",
      remittance_information_unstructured: "Marketing retainer fee for April 2024",
      transaction_currency: "EUR",
      transaction_amount: 1200.00,
      booking_date: date_this_month.(12),
      organization_id: hello_kitty.id
    },
    %{
      internal_transaction_id: "txn_023",
      debtor_name: "Beta Solutions LLC",
      creditor_name: "Hello Kitty Inc.",
      remittance_information_unstructured: "Payment for Q2 SaaS subscription",
      transaction_currency: "EUR",
      transaction_amount: 299.99,
      booking_date: date_this_month.(1),
      organization_id: hello_kitty.id
    },
    %{
      internal_transaction_id: "txn_024",
      debtor_name: "Hello Kitty Inc.",
      creditor_name: "Sigma Logistics",
      remittance_information_unstructured: "April 2024 freight and transport services",
      transaction_currency: "GBP",
      transaction_amount: 1900.00,
      booking_date: date_this_month.(2),
      organization_id: hello_kitty.id
    },
    %{
      internal_transaction_id: "txn_025",
      debtor_name: "Theta Electronics",
      creditor_name: "Hello Kitty Inc.",
      remittance_information_unstructured: "Final installment for hardware integration project",
      transaction_currency: "USD",
      transaction_amount: 4500.00,
      booking_date: date_this_month.(3),
      organization_id: hello_kitty.id
    }
  ]

  Finances.create_or_update_transactions(transactions)

  # ---------------------------------------------------------------------------
  # Current month — Sales invoices (KSeF test scenarios)
  # These showcase KSeF submission states; they are NOT matched to transactions
  # so they won't appear on the analysis dashboard (by design — they're
  # invoicing-workflow items, not yet confirmed by a bank transaction).
  # ---------------------------------------------------------------------------

  inv_number_prefix = "#{String.pad_leading("#{today.month}", 2, "0")}/#{today.year}"

  existing_invoice =
    Repo.one(
      from(si in SalesInvoices.SalesInvoice,
        where: si.invoice_number == ^"01/#{inv_number_prefix}" and si.organization_id == ^hello_kitty.id,
        limit: 1
      )
    )

  if is_nil(existing_invoice) do
    SalesInvoices.create_sales_invoice(
      %SalesInvoices.SalesInvoice{organization_id: hello_kitty.id},
      %{
        "invoice_number" => "01/#{inv_number_prefix}",
        "invoice_type" => "poland",
        "issue_date" => date_this_month.(15),
        "sale_date" => date_this_month.(15),
        "due_date" => date_this_month.(28),
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
        where: si.invoice_number == ^"02/#{inv_number_prefix}" and si.organization_id == ^hello_kitty.id,
        limit: 1
      )
    )

  if is_nil(ksef_success_invoice) do
    {:ok, invoice} =
      SalesInvoices.create_sales_invoice(
        %SalesInvoices.SalesInvoice{organization_id: hello_kitty.id},
        %{
          "invoice_number" => "02/#{inv_number_prefix}",
          "invoice_type" => "poland",
          "issue_date" => date_this_month.(10),
          "sale_date" => date_this_month.(10),
          "due_date" => date_this_month.(24),
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
      locked_at: DateTime.truncate(DateTime.utc_now(), :second)
    })
    |> Repo.update!()
  end

  ksef_sending_invoice =
    Repo.one(
      from(si in SalesInvoices.SalesInvoice,
        where: si.invoice_number == ^"03/#{inv_number_prefix}" and si.organization_id == ^hello_kitty.id,
        limit: 1
      )
    )

  if is_nil(ksef_sending_invoice) do
    {:ok, invoice} =
      SalesInvoices.create_sales_invoice(
        %SalesInvoices.SalesInvoice{organization_id: hello_kitty.id},
        %{
          "invoice_number" => "03/#{inv_number_prefix}",
          "invoice_type" => "poland",
          "issue_date" => date_this_month.(5),
          "sale_date" => date_this_month.(5),
          "due_date" => date_this_month.(19),
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
      locked_at: DateTime.truncate(DateTime.utc_now(), :second)
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
        where: si.invoice_number == ^"04/#{inv_number_prefix}" and si.organization_id == ^hello_kitty.id,
        limit: 1
      )
    )

  if is_nil(ksef_failed_invoice) do
    {:ok, invoice} =
      SalesInvoices.create_sales_invoice(
        %SalesInvoices.SalesInvoice{organization_id: hello_kitty.id},
        %{
          "invoice_number" => "04/#{inv_number_prefix}",
          "invoice_type" => "poland",
          "issue_date" => date_this_month.(3),
          "sale_date" => date_this_month.(3),
          "due_date" => date_this_month.(17),
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
      locked_at: DateTime.truncate(DateTime.utc_now(), :second)
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

  # =========================================================================
  # Analysis dashboard showcase — M-1 (1 month ago)
  #
  # All invoices here are matched to transactions and tagged, demonstrating
  # the full analysis workflow a developer will see on /analiza.
  #
  #   Sales invoice  → Acme dev services  12,300 PLN  → tagged :company
  #   Sales invoice  → Deutsche Tech       4,000 EUR  → untagged
  #   Cost invoice   → Cloud hosting      -1,200 PLN  → tagged project:Firmowid
  #   Cost invoice   → Office supplies      -450 PLN  → untagged
  # =========================================================================

  m1_sale_date = date_months_ago.(1, 15)
  m1_issue_date = date_months_ago.(1, 16)
  m1_due_date = date_months_ago.(1, 28)
  m1_booking = date_months_ago.(1, 20)
  now = DateTime.truncate(DateTime.utc_now(), :second)

  # — M-1 transactions (matched to invoices below) —

  m1_txns =
    for {itid, creditor, debtor, amount, currency} <- [
          {"m1_sale_acme", "Hello Kitty Inc.", "Acme Corporation", 12_300.00, "PLN"},
          {"m1_sale_deutsche", "Hello Kitty Inc.", "Deutsche Tech GmbH", 4_000.00, "EUR"},
          {"m1_cost_cloud", "OVH Cloud Sp. z o.o.", "Hello Kitty Inc.", -1_200.00, "PLN"},
          {"m1_cost_office", "Biuro Plus Sp. z o.o.", "Hello Kitty Inc.", -450.00, "PLN"}
        ] do
      txn_map = %{
        internal_transaction_id: itid,
        creditor_name: creditor,
        creditor_account: "N/A",
        debtor_name: debtor,
        debtor_account: "N/A",
        transaction_amount: amount,
        transaction_currency: currency,
        booking_date: m1_booking,
        bank_account_id: bank_account.id,
        organization_id: hello_kitty.id,
        skip_invoicing: false
      }

      existing =
        Repo.one(
          from(t in Finances.Transaction,
            where:
              t.internal_transaction_id == ^itid and
                t.organization_id == ^hello_kitty.id,
            limit: 1
          )
        )

      case existing do
        nil ->
          Repo.insert!(%Finances.Transaction{
            id: Ecto.UUID.generate(),
            internal_transaction_id: txn_map.internal_transaction_id,
            creditor_name: txn_map.creditor_name,
            creditor_account: txn_map.creditor_account,
            debtor_name: txn_map.debtor_name,
            debtor_account: txn_map.debtor_account,
            transaction_amount: txn_map.transaction_amount,
            transaction_currency: txn_map.transaction_currency,
            booking_date: txn_map.booking_date,
            bank_account_id: txn_map.bank_account_id,
            organization_id: txn_map.organization_id,
            skip_invoicing: txn_map.skip_invoicing,
            inserted_at: now,
            updated_at: now
          })

        txn ->
          txn
      end
    end

  m1_txn_map = Map.new(m1_txns, &{&1.internal_transaction_id, &1})

  # — M-1 sales invoices —

  m1_prefix =
    (
      d = months_ago.(1)
      "#{String.pad_leading("#{d.month}", 2, "0")}/#{d.year}"
    )

  m1_sale_1 =
    case Repo.one(
           from(si in SalesInvoices.SalesInvoice,
             where: si.invoice_number == ^"01/#{m1_prefix}" and si.organization_id == ^hello_kitty.id,
             limit: 1
           )
         ) do
      nil ->
        {:ok, inv} =
          SalesInvoices.create_sales_invoice(
            %SalesInvoices.SalesInvoice{organization_id: hello_kitty.id},
            %{
              "invoice_number" => "01/#{m1_prefix}",
              "invoice_type" => "poland",
              "issue_date" => m1_issue_date,
              "sale_date" => m1_sale_date,
              "due_date" => m1_due_date,
              "currency" => "PLN",
              "seller_display_name" => "Hello Kitty Inc.",
              "seller_address" => "Lipowa 3D, 30-702, Kraków",
              "seller_nip" => "6161525811",
              "seller_account_number" => "PL58253000082079847123980045",
              "buyer_display_name" => "Acme Corporation Sp. z o.o.",
              "buyer_full_name" => "Acme Corporation Sp. z o.o.",
              "buyer_address" => "ul. Testowa 42, 00-001 Warszawa",
              "buyer_country" => "PL",
              "buyer_id" => "5272830422",
              "buyer_type" => "company",
              "payment_method" => "transfer",
              "is_reverse_charge" => false,
              "is_cash_account" => false,
              "sales_invoice_items" => [
                %{
                  "name" => "Usługi programistyczne",
                  "quantity" => 80,
                  "unit" => "godz.",
                  "unit_price" => 150.00,
                  "vat_rate" => "23"
                }
              ]
            }
          )

        inv

      inv ->
        inv
    end

  m1_sale_2 =
    case Repo.one(
           from(si in SalesInvoices.SalesInvoice,
             where: si.invoice_number == ^"02/#{m1_prefix}" and si.organization_id == ^hello_kitty.id,
             limit: 1
           )
         ) do
      nil ->
        {:ok, inv} =
          SalesInvoices.create_sales_invoice(
            %SalesInvoices.SalesInvoice{organization_id: hello_kitty.id},
            %{
              "invoice_number" => "02/#{m1_prefix}",
              "invoice_type" => "foreign",
              "issue_date" => m1_issue_date,
              "sale_date" => m1_sale_date,
              "due_date" => m1_due_date,
              "currency" => "EUR",
              "seller_display_name" => "Hello Kitty Inc.",
              "seller_address" => "Lipowa 3D, 30-702, Kraków",
              "seller_nip" => "6161525811",
              "seller_account_number" => "PL58253000082079847123980045",
              "buyer_display_name" => "Deutsche Tech GmbH",
              "buyer_full_name" => "Deutsche Tech GmbH",
              "buyer_address" => "Hauptstraße 123, 10115 Berlin",
              "buyer_country" => "DE",
              "buyer_id" => "DE123456789",
              "buyer_type" => "company",
              "payment_method" => "transfer",
              "is_reverse_charge" => true,
              "is_cash_account" => false,
              "sales_invoice_items" => [
                %{
                  "name" => "IT Consulting Services",
                  "quantity" => 20,
                  "unit" => "godz.",
                  "unit_price" => 200.00,
                  "vat_rate" => "np I"
                }
              ]
            }
          )

        inv

      inv ->
        inv
    end

  # — M-1 cost invoices —

  m1_cost_1 =
    case Repo.one(
           from(ci in CostInvoices.CostInvoice,
             where: ci.invoice_identifier == ^"OVH/#{m1_prefix}" and ci.organization_id == ^hello_kitty.id,
             limit: 1
           )
         ) do
      nil ->
        Repo.insert!(%CostInvoices.CostInvoice{
          seller: "OVH Cloud Sp. z o.o.",
          seller_display_name: "OVH Cloud",
          seller_address: "ul. Swobodna 1, 50-088 Wrocław",
          sale_date: m1_sale_date,
          issue_date: m1_issue_date,
          due_date: m1_due_date,
          total_amount: -1_200.00,
          currency: "PLN",
          invoice_identifier: "OVH/#{m1_prefix}",
          description: "Hosting serwerów dedykowanych — środowisko produkcyjne",
          skip_invoicing: false,
          organization_id: hello_kitty.id
        })

      ci ->
        ci
    end

  m1_cost_2 =
    case Repo.one(
           from(ci in CostInvoices.CostInvoice,
             where: ci.invoice_identifier == ^"BP/#{m1_prefix}" and ci.organization_id == ^hello_kitty.id,
             limit: 1
           )
         ) do
      nil ->
        Repo.insert!(%CostInvoices.CostInvoice{
          seller: "Biuro Plus Sp. z o.o.",
          seller_display_name: "Biuro Plus",
          seller_address: "ul. Biurowa 10, 31-200 Kraków",
          sale_date: m1_sale_date,
          issue_date: m1_issue_date,
          due_date: m1_due_date,
          total_amount: -450.00,
          currency: "PLN",
          invoice_identifier: "BP/#{m1_prefix}",
          description: "Artykuły biurowe: papier, tonery, materiały eksploatacyjne",
          skip_invoicing: false,
          organization_id: hello_kitty.id
        })

      ci ->
        ci
    end

  # — M-1 matching (invoice ↔ transaction) —

  CostInvoices.create_cost_invoices_transactions_connection(
    m1_cost_1.id,
    m1_txn_map["m1_cost_cloud"].id,
    hello_kitty.id
  )

  CostInvoices.create_cost_invoices_transactions_connection(
    m1_cost_2.id,
    m1_txn_map["m1_cost_office"].id,
    hello_kitty.id
  )

  SalesInvoices.create_sales_invoices_transactions_connection(
    m1_sale_1.id,
    m1_txn_map["m1_sale_acme"].id,
    hello_kitty.id
  )

  SalesInvoices.create_sales_invoices_transactions_connection(
    m1_sale_2.id,
    m1_txn_map["m1_sale_deutsche"].id,
    hello_kitty.id
  )

  # — M-1 tagging —
  # Sales invoice for Acme → :company (firma overhead)
  Analysis.set_entity_category(:sales_invoice, m1_sale_1.id, :company)
  # Cost invoice for OVH Cloud → project:Firmowid
  firmowid_preloaded = Repo.preload(firmowid, :tag_definition)
  Analysis.set_entity_project_tags(:cost_invoice, m1_cost_1.id, [firmowid_preloaded.tag_definition_id])
  # m1_sale_2 and m1_cost_2 intentionally left untagged

  # =========================================================================
  # Analysis dashboard showcase — M-2 (2 months ago)
  #
  #   Sales invoice  → Acme Q retainer    20,000 PLN  → tagged project:Hepa
  #   Sales invoice  → SV Inc integration  8,500 USD  → tagged projects:Firmowid+Startapp
  #   Cost invoice   → Legal services     -3,000 PLN  → tagged :internal (excluded from totals!)
  #   Cost invoice   → Software licenses  -2,400 EUR  → tagged project:Startapp
  # =========================================================================

  m2_sale_date = date_months_ago.(2, 10)
  m2_issue_date = date_months_ago.(2, 11)
  m2_due_date = date_months_ago.(2, 25)
  m2_booking = date_months_ago.(2, 15)

  # — M-2 transactions —

  m2_txns =
    for {itid, creditor, debtor, amount, currency} <- [
          {"m2_sale_acme_q", "Hello Kitty Inc.", "Acme Corporation", 20_000.00, "PLN"},
          {"m2_sale_sv_int", "Hello Kitty Inc.", "Silicon Valley Inc.", 8_500.00, "USD"},
          {"m2_cost_legal", "Kancelaria Prawna Lex Sp. z o.o.", "Hello Kitty Inc.", -3_000.00, "PLN"},
          {"m2_cost_licenses", "JetBrains s.r.o.", "Hello Kitty Inc.", -2_400.00, "EUR"}
        ] do
      existing =
        Repo.one(
          from(t in Finances.Transaction,
            where:
              t.internal_transaction_id == ^itid and
                t.organization_id == ^hello_kitty.id,
            limit: 1
          )
        )

      case existing do
        nil ->
          Repo.insert!(%Finances.Transaction{
            id: Ecto.UUID.generate(),
            internal_transaction_id: itid,
            creditor_name: creditor,
            creditor_account: "N/A",
            debtor_name: debtor,
            debtor_account: "N/A",
            transaction_amount: amount,
            transaction_currency: currency,
            booking_date: m2_booking,
            bank_account_id: bank_account.id,
            organization_id: hello_kitty.id,
            skip_invoicing: false,
            inserted_at: now,
            updated_at: now
          })

        txn ->
          txn
      end
    end

  m2_txn_map = Map.new(m2_txns, &{&1.internal_transaction_id, &1})

  # — M-2 sales invoices —

  m2_prefix =
    (
      d = months_ago.(2)
      "#{String.pad_leading("#{d.month}", 2, "0")}/#{d.year}"
    )

  m2_sale_1 =
    case Repo.one(
           from(si in SalesInvoices.SalesInvoice,
             where: si.invoice_number == ^"01/#{m2_prefix}" and si.organization_id == ^hello_kitty.id,
             limit: 1
           )
         ) do
      nil ->
        {:ok, inv} =
          SalesInvoices.create_sales_invoice(
            %SalesInvoices.SalesInvoice{organization_id: hello_kitty.id},
            %{
              "invoice_number" => "01/#{m2_prefix}",
              "invoice_type" => "poland",
              "issue_date" => m2_issue_date,
              "sale_date" => m2_sale_date,
              "due_date" => m2_due_date,
              "currency" => "PLN",
              "seller_display_name" => "Hello Kitty Inc.",
              "seller_address" => "Lipowa 3D, 30-702, Kraków",
              "seller_nip" => "6161525811",
              "seller_account_number" => "PL58253000082079847123980045",
              "buyer_display_name" => "Acme Corporation Sp. z o.o.",
              "buyer_full_name" => "Acme Corporation Sp. z o.o.",
              "buyer_address" => "ul. Testowa 42, 00-001 Warszawa",
              "buyer_country" => "PL",
              "buyer_id" => "5272830422",
              "buyer_type" => "company",
              "payment_method" => "transfer",
              "is_reverse_charge" => false,
              "is_cash_account" => false,
              "sales_invoice_items" => [
                %{
                  "name" => "Kwartalny retainer — usługi programistyczne",
                  "quantity" => 1,
                  "unit" => "szt.",
                  "unit_price" => 20_000.00,
                  "vat_rate" => "23"
                }
              ]
            }
          )

        inv

      inv ->
        inv
    end

  m2_sale_2 =
    case Repo.one(
           from(si in SalesInvoices.SalesInvoice,
             where: si.invoice_number == ^"02/#{m2_prefix}" and si.organization_id == ^hello_kitty.id,
             limit: 1
           )
         ) do
      nil ->
        {:ok, inv} =
          SalesInvoices.create_sales_invoice(
            %SalesInvoices.SalesInvoice{organization_id: hello_kitty.id},
            %{
              "invoice_number" => "02/#{m2_prefix}",
              "invoice_type" => "foreign",
              "issue_date" => m2_issue_date,
              "sale_date" => m2_sale_date,
              "due_date" => m2_due_date,
              "currency" => "USD",
              "seller_display_name" => "Hello Kitty Inc.",
              "seller_address" => "Lipowa 3D, 30-702, Kraków",
              "seller_nip" => "6161525811",
              "seller_account_number" => "PL58253000082079847123980045",
              "buyer_display_name" => "Silicon Valley Inc.",
              "buyer_full_name" => "Silicon Valley Inc.",
              "buyer_address" => "1 Infinite Loop, Cupertino, CA 95014",
              "buyer_country" => "US",
              "buyer_id" => "US-EIN-12-3456789",
              "buyer_type" => "company",
              "payment_method" => "transfer",
              "is_reverse_charge" => false,
              "is_cash_account" => false,
              "sales_invoice_items" => [
                %{
                  "name" => "Platform integration & API development",
                  "quantity" => 50,
                  "unit" => "godz.",
                  "unit_price" => 170.00,
                  "vat_rate" => "np II"
                }
              ]
            }
          )

        inv

      inv ->
        inv
    end

  # — M-2 cost invoices —

  m2_cost_1 =
    case Repo.one(
           from(ci in CostInvoices.CostInvoice,
             where: ci.invoice_identifier == ^"LEX/#{m2_prefix}" and ci.organization_id == ^hello_kitty.id,
             limit: 1
           )
         ) do
      nil ->
        Repo.insert!(%CostInvoices.CostInvoice{
          seller: "Kancelaria Prawna Lex Sp. z o.o.",
          seller_display_name: "Kancelaria Lex",
          seller_address: "ul. Sądowa 7, 00-950 Warszawa",
          sale_date: m2_sale_date,
          issue_date: m2_issue_date,
          due_date: m2_due_date,
          total_amount: -3_000.00,
          currency: "PLN",
          invoice_identifier: "LEX/#{m2_prefix}",
          description: "Obsługa prawna — przelew między kontami spółki (transakcja wewnętrzna)",
          skip_invoicing: false,
          organization_id: hello_kitty.id
        })

      ci ->
        ci
    end

  m2_cost_2 =
    case Repo.one(
           from(ci in CostInvoices.CostInvoice,
             where: ci.invoice_identifier == ^"JB/#{m2_prefix}" and ci.organization_id == ^hello_kitty.id,
             limit: 1
           )
         ) do
      nil ->
        Repo.insert!(%CostInvoices.CostInvoice{
          seller: "JetBrains s.r.o.",
          seller_display_name: "JetBrains",
          seller_address: "Na Hřebenech II 1718/10, Prague",
          sale_date: m2_sale_date,
          issue_date: m2_issue_date,
          due_date: m2_due_date,
          total_amount: -2_400.00,
          currency: "EUR",
          invoice_identifier: "JB/#{m2_prefix}",
          description: "Roczna licencja All Products Pack — 6 stanowisk",
          skip_invoicing: false,
          organization_id: hello_kitty.id
        })

      ci ->
        ci
    end

  # — M-2 matching —

  CostInvoices.create_cost_invoices_transactions_connection(
    m2_cost_1.id,
    m2_txn_map["m2_cost_legal"].id,
    hello_kitty.id
  )

  CostInvoices.create_cost_invoices_transactions_connection(
    m2_cost_2.id,
    m2_txn_map["m2_cost_licenses"].id,
    hello_kitty.id
  )

  SalesInvoices.create_sales_invoices_transactions_connection(
    m2_sale_1.id,
    m2_txn_map["m2_sale_acme_q"].id,
    hello_kitty.id
  )

  SalesInvoices.create_sales_invoices_transactions_connection(
    m2_sale_2.id,
    m2_txn_map["m2_sale_sv_int"].id,
    hello_kitty.id
  )

  # — M-2 tagging —
  hepa_preloaded = Repo.preload(hepa, :tag_definition)
  startapp_preloaded = Repo.preload(startapp, :tag_definition)

  # Sales invoice for Acme retainer → project:Hepa
  Analysis.set_entity_project_tags(:sales_invoice, m2_sale_1.id, [hepa_preloaded.tag_definition_id])
  # Sales invoice for SV Inc → projects:Firmowid + Startapp (multi-tag)
  Analysis.set_entity_project_tags(:sales_invoice, m2_sale_2.id, [
    firmowid_preloaded.tag_definition_id,
    startapp_preloaded.tag_definition_id
  ])

  # Cost invoice for Legal → :internal (excluded from totals — dev can verify it disappears)
  Analysis.set_entity_category(:cost_invoice, m2_cost_1.id, :internal)
  # Cost invoice for JetBrains → project:Startapp
  Analysis.set_entity_project_tags(:cost_invoice, m2_cost_2.id, [startapp_preloaded.tag_definition_id])

  # =========================================================================
  # Evil org — separate tenant for authorization testing
  # =========================================================================

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
      sale_date: date_this_month.(18),
      issue_date: date_this_month.(19),
      due_date: date_this_month.(28),
      total_amount: -99_999.99,
      currency: "PLN",
      invoice_identifier: "SECRET/#{today.year}/#{today.month}/666",
      description: "Top secret confidential services - DO NOT SHARE",
      skip_invoicing: false,
      organization_id: evil_org.id,
      seller_address: "Confidential Address 1, Secret Location"
    })
  end

  evil_inv_prefix = "#{String.pad_leading("#{today.month}", 2, "0")}/#{today.year}"

  existing_evil_invoice =
    Repo.one(
      from(si in SalesInvoices.SalesInvoice,
        where: si.invoice_number == ^"EVIL/#{evil_inv_prefix}/001" and si.organization_id == ^evil_org.id,
        limit: 1
      )
    )

  if is_nil(existing_evil_invoice) do
    SalesInvoices.create_sales_invoice(
      %SalesInvoices.SalesInvoice{organization_id: evil_org.id},
      %{
        "invoice_number" => "EVIL/#{evil_inv_prefix}/001",
        "invoice_type" => "poland",
        "issue_date" => date_this_month.(5),
        "sale_date" => date_this_month.(5),
        "due_date" => date_this_month.(19),
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
  Seeds loaded successfully!
  =========================

  Analysis dashboard (/analiza) showcase:
    Current month  — unmatched transactions & invoices (raw bank feed + KSeF states)
    1 month ago    — matched invoices: :company tag, project:Firmowid tag, untagged
    2 months ago   — matched invoices: :internal tag (excluded), project:Hepa,
                     multi-project (Firmowid+Startapp), project:Startapp

  KSeF Test Environment:
    URL: https://ap-test.ksef.mf.gov.pl/web/tokens/generate-token
    NIP: 6161525811 (Hello Kitty Inc.)
  """)
end)
