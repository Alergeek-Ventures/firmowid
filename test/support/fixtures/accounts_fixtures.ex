defmodule Firmowid.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Firmowid.Accounts` context.
  """

  alias Firmowid.Accounts.User
  alias Firmowid.Repo

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"
  def valid_user_password, do: "hello world!"

  def unique_identifcation_number, do: System.unique_integer() |> Integer.to_string()

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_user_email(),
      password: valid_user_password()
    })
  end

  def admin_fixture(attrs \\ %{}) do
    user_fixture(Map.merge(%{system_role: "superuser"}, attrs))
  end

  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> Firmowid.Accounts.register_user()

    {:ok, organization} =
      Firmowid.Accounts.create_organization(
        %{
          "identification_number" => unique_identifcation_number(),
          "name" => "Test Organization",
          "owner_id" => user.id
        },
        user
      )

    Firmowid.Accounts.update_user(user, Map.take(attrs, [:system_role]))

    Repo.put_org_id(organization.id)

    user
    |> User.organization_changeset(%{organization_id: organization.id})
    |> Repo.update!(skip_organization_id: true)
  end

  def extract_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end
end
