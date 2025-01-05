alias Firmowid.Accounts

{:ok, franek} =
  Accounts.register_user(%{
    email: "franek@alergeek.ventures",
    password: "kolejka123456"
  })

{:ok, _av} =
  Accounts.create_organization(
    %{
      "name" => "Alergeek Ventures spółka z ograniczoną odpowiedzialnością",
      "slug" => "Alergeek Ventures",
      "identification_number" => "PL1234567891",
      "address" => "Lipowa 3D, 30-702, Kraków",
      "owner_id" => franek.id
    },
    franek
  )
