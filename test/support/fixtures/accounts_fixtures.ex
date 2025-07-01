defmodule Firmowid.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Firmowid.Accounts` context.
  """

  alias Firmowid.Accounts
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

  @spec admin_fixture() :: any()
  def admin_fixture(attrs \\ %{}) do
    user_fixture(Map.merge(%{role: :admin}, attrs))
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

    Repo.put_org_id(organization.id)

    {:ok, user} =
      Accounts.get_user!(user.id)
      |> Firmowid.Accounts.update_user(
        Map.merge(
          %{
            role: :employee
          },
          Map.take(attrs, [:role, :system_role])
        )
      )

    user
  end

  def user_in_org_fixture(organization_id, attrs \\ %{}) do
    # register the user without an organization
    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> Firmowid.Accounts.register_user()

    Repo.put_org_id(organization_id)

    # update the user to be part of the specified organization
    {:ok, user} =
      user
      |> Ecto.Changeset.change(%{organization_id: organization_id})
      |> Repo.update()

    {:ok, user} =
      Accounts.get_user!(user.id)
      |> Firmowid.Accounts.update_user(
        Map.merge(
          %{
            role: :employee
          },
          Map.take(attrs, [:role, :system_role])
        )
      )

    user
  end

  def extract_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end
end
