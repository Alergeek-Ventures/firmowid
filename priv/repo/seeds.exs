# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Firmowid.Repo.insert!(%Firmowid.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias Firmowid.Accounts

{:ok, franek} =
  Accounts.register_user(%{
    email: "franek@alergeek.ventures",
    password: "kolejka123456"
  })

{:ok, av} =
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
