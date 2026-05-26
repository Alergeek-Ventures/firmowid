defmodule Firmowid.FinancesFixtures do
  @moduledoc """
  Test helpers for creating finance-domain records.
  """

  alias Firmowid.Ash.Finances.BankAccount

  @doc """
  Creates a bank account fixture for the user's organization.
  """
  @spec bank_account_fixture!(%{organization_id: Ecto.UUID.t()}, map()) :: BankAccount.t()
  def bank_account_fixture!(user, attrs \\ %{}) do
    bank_account_fixture_for_organization!(user.organization_id, attrs)
  end

  @doc """
  Creates a bank account fixture for the given organization.
  """
  @spec bank_account_fixture_for_organization!(Ecto.UUID.t(), map()) :: BankAccount.t()
  def bank_account_fixture_for_organization!(organization_id, attrs \\ %{}) do
    unique = System.unique_integer([:positive])

    %{
      iban: unique_iban(unique),
      institution_name: "Manual",
      owner_name: "Test Owner",
      currency: "PLN",
      name: "Test bank account #{unique}",
      is_default: false,
      organization_id: organization_id
    }
    |> Map.merge(attrs)
    |> then(&Ash.Seed.seed!(BankAccount, &1))
  end

  defp unique_iban(unique) do
    unique
    |> Integer.to_string()
    |> String.pad_leading(26, "0")
    |> String.slice(-26..-1)
    |> then(&"PL#{&1}")
  end
end
