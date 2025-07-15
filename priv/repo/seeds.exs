alias Firmowid.Timetracker
alias Firmowid.Repo
alias Firmowid.Accounts
alias Firmowid.Finances

Repo.transaction(fn ->
  {:ok, franek} =
    Accounts.register_user(%{
      email: "franek@alergeek.ventures",
      password: "kolejka123456"
    })

  {:ok, bartek} =
    Accounts.register_user(%{
      email: "bartek@alergeek.ventures",
      password: "kolejka123456"
    })

  franek
  |> Accounts.update_user(%{
    system_role: :superuser,
    role: :admin
  })

  {:ok, av} =
    Accounts.create_organization(
      %{
        "name" => "Alergeek Ventures spółka z ograniczoną odpowiedzialnością",
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

  # Add sample transactions for testing search functionality
  transactions = [
    %{
      internal_transaction_id: "txn_001",
      debtor_name: "Acme Corporation",
      creditor_name: "Alergeek Ventures",
      remittance_information_unstructured:
        "Invoice #INV-2024-001 for software development services",
      transaction_currency: "USD",
      transaction_amount: 5000.00,
      booking_date: ~D[2024-01-15],
      organization_id: av.id
    },
    %{
      internal_transaction_id: "txn_002",
      debtor_name: "Beta Solutions LLC",
      creditor_name: "Alergeek Ventures",
      remittance_information_unstructured: "Monthly subscription payment for SaaS platform",
      transaction_currency: "EUR",
      transaction_amount: 299.99,
      booking_date: ~D[2024-01-20],
      organization_id: av.id
    },
    %{
      internal_transaction_id: "txn_003",
      debtor_name: "Gamma Technologies",
      creditor_name: "Alergeek Ventures",
      remittance_information_unstructured: "Consulting fee for Q1 2024 project",
      transaction_currency: "PLN",
      transaction_amount: 15000.00,
      booking_date: ~D[2024-02-01],
      organization_id: av.id
    },
    %{
      internal_transaction_id: "txn_004",
      debtor_name: "Alergeek Ventures",
      creditor_name: "Delta Hosting Services",
      remittance_information_unstructured: "Cloud hosting payment for January 2024",
      transaction_currency: "USD",
      transaction_amount: 250.00,
      booking_date: ~D[2024-01-31],
      organization_id: av.id
    },
    %{
      internal_transaction_id: "txn_005",
      debtor_name: "Epsilon Marketing",
      creditor_name: "Alergeek Ventures",
      remittance_information_unstructured: "Digital marketing campaign Q1 2024",
      transaction_currency: "EUR",
      transaction_amount: 1200.00,
      booking_date: ~D[2024-02-15],
      organization_id: av.id
    }
  ]

  Finances.create_or_update_transactions(transactions)
end)
