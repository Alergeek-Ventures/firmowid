alias Firmowid.Timetracker
alias Firmowid.Repo
alias Firmowid.Accounts

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

  Repo.put_org_id(av.id)

  {:ok, invite} = Accounts.create_organization_invites(av.id, franek.id)
  Accounts.consume_organization_invite(invite.invite_code, bartek.id)

  {:ok, firmowid} = Timetracker.create_project(%{name: "Firmowid"})

  {:ok, _} = Timetracker.create_project(%{name: "Kvantab"})

  Timetracker.add_user_to_project(franek.id, firmowid.id)
  Timetracker.add_user_to_project(bartek.id, firmowid.id)
end)
