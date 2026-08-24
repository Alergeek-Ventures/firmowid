defmodule Firmowid.Ash.Invoicing.Changes.ValidateCostInvoiceCorrectionCurrency do
  @moduledoc """
  Ensures a linked cost invoice correction uses its original invoice currency.

  Corrections received before their original invoice remain valid orphans.
  """
  use Ash.Resource.Change

  alias Firmowid.Ash.Invoicing.CostInvoice

  @correction_invoice_types [:kor, :kor_zal, :kor_roz]

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      case original_invoice(changeset, context) do
        {:ok, nil} ->
          changeset

        {:ok, original_invoice} ->
          validate_currency(changeset, original_invoice)

        {:error, error} ->
          Ash.Changeset.add_error(changeset, error)
      end
    end)
  end

  defp original_invoice(changeset, context) do
    invoice_type = Ash.Changeset.get_attribute(changeset, :invoice_type)

    original_invoice_ksef_number =
      Ash.Changeset.get_attribute(changeset, :original_invoice_ksef_number)

    if invoice_type in @correction_invoice_types and is_binary(original_invoice_ksef_number) do
      CostInvoice
      |> Ash.Query.filter(ksef_number == ^original_invoice_ksef_number)
      |> Ash.read_one(Ash.Context.to_opts(context))
    else
      {:ok, nil}
    end
  end

  defp validate_currency(changeset, original_invoice) do
    amount = Ash.Changeset.get_attribute(changeset, :amount)

    if Money.to_currency_code(amount) == Money.to_currency_code(original_invoice.amount) do
      changeset
    else
      Ash.Changeset.add_error(changeset,
        field: :currency,
        message: "must match the original invoice currency"
      )
    end
  end
end
