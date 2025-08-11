alias Firmowid.Accounts
alias Firmowid.Blobs
alias Firmowid.CostInvoices
alias Firmowid.Finances
alias Firmowid.Repo
alias Firmowid.Timetracker

Repo.transaction(fn ->
  {:ok, franek} =
    Accounts.register_user(%{
      email: "piotr@firmowid.pl",
      password: "kolejka123456"
    })

  {:ok, bartek} =
    Accounts.register_user(%{
      email: "hyzio@firmowid.pl",
      password: "kolejka123456"
    })

  Accounts.update_user(franek, %{system_role: :superuser, role: :admin})

  {:ok, av} =
    Accounts.create_organization(
      %{
        "name" => "Hello Kitty Inc. spółka z ograniczoną odpowiedzialnością",
        "identification_number" => "PL1234567891",
        "address" => "Lipowa 3D, 30-702, Kraków",
        "owner_id" => franek.id
      },
      franek
    )

  Repo.put_org_id(av.id)

  {:ok, invite} = Accounts.create_organization_invites(av.id, franek.id)
  Accounts.consume_organization_invite(invite.invite_code, bartek.id)

  {:ok, firmowid} = Timetracker.create_project(%{name: "Firmowid"})

  {:ok, _} = Timetracker.create_project(%{name: "Kvantab"})

  Timetracker.add_user_to_project(franek.id, firmowid.id)
  Timetracker.add_user_to_project(bartek.id, firmowid.id)

  # --- Insert Mobile Vikings cost invoice and related data for Hello Kitty Inc. ---

  # Insert blob for the invoice PDF
  blob =
    Repo.insert!(%Blobs.Blob{
      id: "4ff0d0b1-3298-4b80-9d53-a71d0efc4cad",
      blob_path: "4ff0d0b1-3298-4b80-9d53-a71d0efc4cad/01957157-6ba5-7fb9-85cc-6fdbb7fbf181.pdf",
      blob_checksum: "ff2c9062d9a8189522a59805210ebe5d2211e5868d724a47863a0b740d6892b6",
      original_filename: "mobilevikings-2025-03.pdf",
      organization_id: av.id
    })

  # Insert mock requisition (required for bank account)
  mock_requisition =
    Repo.insert!(%Firmowid.BankData.Requisition{
      id: "b42a914c-d658-46bb-ab4c-950967fbebe1",
      status: :accepted,
      organization_id: av.id
    })

  # Insert bank account (if not already present)
  bank_account =
    Repo.insert!(%Finances.BankAccount{
      id: "5e99d40d-8bcb-4088-b6a1-08950daa5ec2",
      iban: "PL58253000082079847123980045",
      institution_id: "NEST_BANK_CORPORATE_PL",
      institution_name: "Nest Bank Corporate",
      owner_name: "Hello Kitty Inc.",
      gocardless_id: "c5831186-ca3e-4edc-a4f5-a48b1d1ead51",
      currency: "PLN",
      organization_id: av.id,
      is_default: true,
      requisition_id: mock_requisition.id
    })

  # Insert transactions
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
      organization_id: av.id,
      inserted_at: DateTime.from_naive!(inserted_at, "Etc/UTC"),
      updated_at: DateTime.from_naive!(updated_at, "Etc/UTC")
    })
  end

  # Insert the cost invoice itself
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
    organization_id: av.id,
    seller_address: "plac Grunwaldzki 23, 50-365 Wroclaw"
  })

  # Add sample transactions for testing search functionality
  transactions = [
    %{
      internal_transaction_id: "txn_001",
      debtor_name: "Acme Corporation",
      creditor_name: "Hello Kitty Inc.",
      remittance_information_unstructured: "Invoice #INV-2024-001 for software development services",
      transaction_currency: "USD",
      transaction_amount: 5000.00,
      booking_date: ~D[2024-01-15],
      organization_id: av.id
    },
    %{
      internal_transaction_id: "txn_002",
      debtor_name: "Beta Solutions LLC",
      creditor_name: "Hello Kitty Inc.",
      remittance_information_unstructured: "Monthly subscription payment for SaaS platform",
      transaction_currency: "EUR",
      transaction_amount: 299.99,
      booking_date: ~D[2024-01-20],
      organization_id: av.id
    },
    %{
      internal_transaction_id: "txn_003",
      debtor_name: "Gamma Technologies",
      creditor_name: "Hello Kitty Inc.",
      remittance_information_unstructured: "Consulting fee for Q1 2024 project",
      transaction_currency: "PLN",
      transaction_amount: 15_000.00,
      booking_date: Date.utc_today(),
      organization_id: av.id
    },
    %{
      internal_transaction_id: "txn_004",
      debtor_name: "Hello Kitty Inc.",
      creditor_name: "Delta Hosting Services",
      remittance_information_unstructured: "Cloud hosting payment for January 2024",
      transaction_currency: "USD",
      transaction_amount: 250.00,
      booking_date: Date.utc_today(),
      organization_id: av.id
    },
    %{
      internal_transaction_id: "txn_005",
      debtor_name: "Epsilon Marketing",
      creditor_name: "Hello Kitty Inc.",
      remittance_information_unstructured: "Digital marketing campaign Q1 2024",
      transaction_currency: "EUR",
      transaction_amount: 1200.00,
      booking_date: Date.utc_today(),
      organization_id: av.id
    }
  ]

  Finances.create_or_update_transactions(transactions)
end)
