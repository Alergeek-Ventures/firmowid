defmodule Firmowid.BankData.Transaction do
  use Ecto.Schema

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
    try do
      api_object_snake_cased =
        api_object_snake_cased
        |> Map.put(
          "transaction_currency",
          api_object_snake_cased |> Map.get("transaction_amount") |> Map.get("currency")
        )

      api_object_snake_cased =
        if Map.has_key?(api_object_snake_cased, "creditor_account") do
          Map.replace(
            api_object_snake_cased,
            "creditor_account",
            api_object_snake_cased |> Map.get("creditor_account") |> Map.get("iban")
          )
        else
          api_object_snake_cased
        end

      api_object_snake_cased =
        if Map.has_key?(api_object_snake_cased, "debtor_account") do
          api_object_snake_cased
          |> Map.replace(
            "debtor_account",
            api_object_snake_cased |> Map.get("debtor_account") |> Map.get("iban")
          )
        else
          api_object_snake_cased
        end

      api_object_snake_cased
      |> Map.replace(
        "transaction_amount",
        api_object_snake_cased |> Map.get("transaction_amount") |> Map.get("amount")
      )
    rescue
      error ->
        Sentry.capture_exception(error, stacktrace: __STACKTRACE__)

        api_object_snake_cased
    end
  end

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
    try do
      transaction = transaction_changeset.changes

      if transaction.creditor_name == "Nest Bank S.A." and
           transaction.remittance_information_unstructured
           |> String.contains?("Nr karty") do
        [new_creditor_name | [description | _]] =
          transaction.remittance_information_unstructured
          |> String.split("Nr karty")

        new_creditor_name =
          new_creditor_name
          |> String.trim()
          |> String.replace_trailing(",", "")

        description = ("Nr karty " <> description) |> String.trim()

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
        Sentry.capture_exception(error, stacktrace: __STACKTRACE__)

        transaction_changeset
    end
  end
end
