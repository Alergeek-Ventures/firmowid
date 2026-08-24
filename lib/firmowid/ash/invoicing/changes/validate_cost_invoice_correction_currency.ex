defmodule Firmowid.Ash.Invoicing.Changes.ValidateCostInvoiceCorrectionCurrency do
  @moduledoc """
  Ensures linked cost invoice corrections and originals use the same currency.

  Corrections received before their original invoice remain valid orphans.
  """
  use Ash.Resource.Change

  alias Firmowid.Ash.Invoicing.CostInvoice

  @correction_invoice_types [:kor, :kor_zal, :kor_roz]

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      case linked_invoices(changeset, context) do
        {:ok, linked_invoices} ->
          validate_currency(changeset, linked_invoices)

        {:error, error} ->
          Ash.Changeset.add_error(changeset, error)
      end
    end)
  end

  defp linked_invoices(changeset, context) do
    invoice_type = Ash.Changeset.get_attribute(changeset, :invoice_type)

    original_invoice_ksef_number =
      Ash.Changeset.get_attribute(changeset, :original_invoice_ksef_number)

    ksef_number = Ash.Changeset.get_attribute(changeset, :ksef_number)

    cond do
      invoice_type in @correction_invoice_types and is_binary(original_invoice_ksef_number) ->
        original_invoice(original_invoice_ksef_number, context)

      is_binary(ksef_number) ->
        CostInvoice
        |> Ash.Query.filter(original_invoice_ksef_number == ^ksef_number)
        |> Ash.read(Ash.Context.to_opts(context))

      true ->
        {:ok, []}
    end
  end

  defp original_invoice(ksef_number, context) do
    case CostInvoice
         |> Ash.Query.filter(ksef_number == ^ksef_number)
         |> Ash.read_one(Ash.Context.to_opts(context)) do
      {:ok, nil} -> {:ok, []}
      {:ok, invoice} -> {:ok, [invoice]}
      {:error, error} -> {:error, error}
    end
  end

  defp validate_currency(changeset, linked_invoices) do
    amount = Ash.Changeset.get_attribute(changeset, :amount)

    if Enum.all?(
         linked_invoices,
         &(Money.to_currency_code(amount) == Money.to_currency_code(&1.amount))
       ) do
      changeset
    else
      Ash.Changeset.add_error(changeset,
        field: :amount,
        message: "must match linked invoice currency"
      )
    end
  end
end
