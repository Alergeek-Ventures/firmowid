defmodule Firmowid.BankData.Transaction do
  @moduledoc false
  use Firmowid.Schema

  import Ecto.Changeset

  embedded_schema do
    field :transaction_id, :string
    field :internal_transaction_id, :string
    field :debtor_name, :string, default: "N/A"
    field :debtor_account, :string, default: "N/A"
    field :creditor_name, :string, default: "N/A"
    field :creditor_account, :string, default: "N/A"
    field :transaction_amount, :float
    field :transaction_currency, :string
    field :booking_date, :date
    field :value_date, :date
    field :remittance_information_unstructured, :string
  end

  def map_camel_to_snake(api_object) do
    Recase.Enumerable.convert_keys(
      api_object,
      &Recase.to_snake/1
    )
  end

  def flatten_api_response(api_object_snake_cased) do
    api_object_snake_cased =
      Map.put(
        api_object_snake_cased,
        "transaction_currency",
        api_object_snake_cased |> Map.get("transaction_amount") |> Map.get("currency")
      )

    api_object_snake_cased =
      Map.replace(
        api_object_snake_cased,
        "creditor_account",
        api_object_snake_cased |> Map.get("creditor_account") |> extract_iban_or_bban()
      )

    api_object_snake_cased =
      Map.replace(
        api_object_snake_cased,
        "debtor_account",
        api_object_snake_cased |> Map.get("debtor_account") |> extract_iban_or_bban()
      )

    Map.replace(
      api_object_snake_cased,
      "transaction_amount",
      api_object_snake_cased |> Map.get("transaction_amount") |> Map.get("amount")
    )
  end

  defp extract_iban_or_bban(nil), do: "N/A"
  defp extract_iban_or_bban(%{"iban" => iban}), do: iban
  defp extract_iban_or_bban(%{"bban" => bban}), do: bban

  def changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :transaction_id,
      :internal_transaction_id,
      :debtor_name,
      :debtor_account,
      :creditor_name,
      :creditor_account,
      :transaction_currency,
      :transaction_amount,
      :booking_date,
      :value_date,
      :remittance_information_unstructured
    ])
    |> convert_nest_bank_card_transaction()
  end

  defp convert_nest_bank_card_transaction(transaction_changeset) do
    creditor_name = get_field(transaction_changeset, :creditor_name, "")

    remittance_information_unstructured =
      get_field(transaction_changeset, :remittance_information_unstructured, "")

    if creditor_name == "Nest Bank S.A." and
         String.contains?(remittance_information_unstructured, "Nr karty") do
      [new_creditor_name | [description | _]] = String.split(remittance_information_unstructured, "Nr karty")

      new_creditor_name =
        new_creditor_name
        |> String.trim()
        |> String.replace_trailing(",", "")

      description = String.trim("Nr karty " <> description)

      transaction_changeset
      |> put_change(
        :creditor_name,
        new_creditor_name
      )
      |> put_change(
        :remittance_information_unstructured,
        description
      )
    else
      transaction_changeset
    end
  rescue
    error ->
      ErrorTracker.report(error, __STACKTRACE__)

      transaction_changeset
  end
end
