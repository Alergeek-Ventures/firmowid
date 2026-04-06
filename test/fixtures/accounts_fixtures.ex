defmodule Firmowid.AccountsFixtures do
  @moduledoc """
  Test helpers for creating users and organizations via the Ash Core domain.
  """

  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Core.User

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"
  def valid_user_password, do: "hello world!!"

  defp unique_nip do
    [:positive]
    |> System.unique_integer()
    |> Integer.to_string()
    |> String.pad_leading(10, "0")
    |> String.slice(-10..-1)
  end

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_user_email(),
      password: valid_user_password()
    })
  end

  @doc """
  Creates a user with an organization. Accepts optional attrs:
    - `:email` — defaults to a unique email
    - `:password` — defaults to `valid_user_password/0`
    - `:role` — defaults to `:employee`
    - `:organization_id` — when provided, joins that org instead of creating a new one
  """
  @spec user_fixture(map()) :: User.t()
  def user_fixture(attrs \\ %{}) do
    email = attrs[:email] || unique_user_email()
    password = attrs[:password] || valid_user_password()

    user =
      Core.register_with_password!(%{email: email, password: password},
        authorize?: false,
        actor: %{}
      )

    user =
      case attrs[:organization_id] do
        nil ->
          org =
            Core.create_organization!(
              %{nip: unique_nip(), name: "Test Organization", owner_id: user.id},
              authorize?: false,
              actor: %{}
            )

          Core.set_organization!(user, %{organization_id: org.id},
            authorize?: false,
            actor: %{},
            tenant: org.id
          )

        org_id ->
          Core.set_organization!(user, %{organization_id: org_id},
            authorize?: false,
            actor: %{},
            tenant: org_id
          )
      end

    role = attrs[:role] || :employee
    Core.update_role!(user, %{role: role}, authorize?: false, actor: %{})
  end

  @doc """
  Creates a user with `:admin` role. Forwards all attrs to `user_fixture/1`.
  """
  @spec admin_fixture(map()) :: User.t()
  def admin_fixture(attrs \\ %{}) do
    user_fixture(Map.merge(%{role: :admin}, attrs))
  end

  @doc """
  Creates a user in an existing organization without creating a new one.
  """
  @spec user_in_org_fixture(Ecto.UUID.t(), map()) :: User.t()
  def user_in_org_fixture(organization_id, attrs \\ %{}) do
    user_fixture(Map.put(attrs, :organization_id, organization_id))
  end

  @doc """
  Intercepts a token from a sent email for use in confirmation / reset-password tests.
  The `fun` receives a URL-building function and should return `{:ok, email}`.
  """
  def extract_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end
end
