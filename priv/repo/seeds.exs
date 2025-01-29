alias Firmowid.Timetracker
alias Firmowid.Repo
alias Firmowid.Accounts

{:ok, franek} =
  Accounts.register_user(%{
    email: "franek@alergeek.ventures",
    password: "kolejka123456"
  })

# easier :x - allows you to visit /admin/dashboard
qry = "UPDATE users SET system_role = 'superuser' WHERE email = 'franek@alergeek.ventures'"
res = Ecto.Adapters.SQL.query!(Repo, qry, [])

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

{:ok, _} = Timetracker.create_project(%{name: "Firmowid", organization_id: av.id})

{:ok, _} = Timetracker.create_project(%{name: "Kvantab", organization_id: av.id})
