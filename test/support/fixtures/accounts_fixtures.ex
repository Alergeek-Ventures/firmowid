defmodule Firmowid.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Firmowid.Accounts` context.
  """

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"
  def valid_user_password, do: "hello world!"

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_user_email(),
      password: valid_user_password()
    })
  end

  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> Firmowid.Accounts.register_user()

    user
  end

  def extract_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end

  @doc """
  Generate a organization_invites.
  """
  def organization_invites_fixture(attrs \\ %{}) do
    {:ok, organization_invites} =
      attrs
      |> Enum.into(%{
        expires_at: ~U[2024-10-05 17:16:00Z],
        invite_code: "some invite_code",
        issued_by: "7488a646-e31f-11e4-aace-600308960662",
        organization_id: "7488a646-e31f-11e4-aace-600308960662"
      })
      |> Firmowid.Accounts.create_organization_invites()

    organization_invites
  end
end
