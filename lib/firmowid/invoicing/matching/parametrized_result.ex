defmodule Firmowid.Invoicing.Matching.ParametrizedResult do
  @enforce_keys [
    :days_lag_le_3,
    :days_lag_le_7,
    :days_lag_le_30,
    :days_lag_gt_30,
    :relative_amount_difference,
    :signed_amount_match,
    :transaction_side_similarity,
    :bank_account_similarity,
    :is_same_currency,
    :amount_present_in_remittance_information_unstructured,
    :invoice_identifier_present_in_remittance_information_unstructured
  ]

  defstruct [
    # days lag buckets
    :days_lag_le_3,
    :days_lag_le_7,
    :days_lag_le_30,
    :days_lag_gt_30,
    # signed ratio of tx.amount / inv.amount, clipped
    :signed_amount_match,
    # relative to the total invoice amount
    :relative_amount_difference,
    # similarity between transaction creditor name and invoice seller name
    :transaction_side_similarity,
    # IBAN similarity (overlap coefficient)
    :bank_account_similarity,
    # whether invoice and transaction are in the same currency
    :is_same_currency,
    # if in the description of the transaction there is a mention of the invoice amount
    :amount_present_in_remittance_information_unstructured,
    # if the invoice identifier (invoice number) is present in the transaction description
    :invoice_identifier_present_in_remittance_information_unstructured
  ]

  @moduledoc """
  For each transaction that might be relevant to the invoice we are matching
  for - we calculate set of parameters, that will be used to rank the transactions.
  """

  alias Akin
  alias Decimal

  alias Firmowid.CostInvoices.CostInvoice
  alias Firmowid.Finances.Transaction
  alias Firmowid.SalesInvoices.SalesInvoice

  @doc """
  Calculate a set of parameters for a given invoice and transaction pair.
  It is later used to rank the transactions (logistic regression).
  """
  @spec generate_parametrized_result(%CostInvoice{} | %SalesInvoice{}, %Transaction{}) ::
          %__MODULE__{}
  def generate_parametrized_result(invoice, transaction) do
    days_diff =
      calculate_difference_in_days(get_invoice_date(invoice), transaction.booking_date) |> abs()

    {le_3, le_7, le_30, gt_30} = days_lag_buckets(days_diff)

    %__MODULE__{
      days_lag_le_3: boolean_to_float(le_3),
      days_lag_le_7: boolean_to_float(le_7),
      days_lag_le_30: boolean_to_float(le_30),
      days_lag_gt_30: boolean_to_float(gt_30),
      signed_amount_match: calculate_signed_amount_match(invoice, transaction),
      relative_amount_difference: calculate_relative_amount_difference(invoice, transaction),
      transaction_side_similarity:
        calculate_transaction_side_similarity(
          get_transaction_side_name(invoice, transaction),
          get_invoice_display_name(invoice)
        ),
      bank_account_similarity:
        calculate_bank_account_similarity(
          get_transaction_side_account(invoice, transaction),
          get_invoice_account_number(invoice)
        ),
      is_same_currency: boolean_to_float(invoice.currency == transaction.transaction_currency),
      amount_present_in_remittance_information_unstructured:
        amount_present_in_remittance_information_unstructured(
          transaction.remittance_information_unstructured,
          get_invoice_amount(invoice),
          invoice.currency
        ),
      invoice_identifier_present_in_remittance_information_unstructured:
        invoice_identifier_present_in_remittance_information_unstructured(
          transaction.remittance_information_unstructured,
          get_invoice_identifier(invoice)
        )
    }
  end

  # Helper functions to extract the correct fields for each invoice type
  defp get_invoice_date(%CostInvoice{due_date: due_date}), do: due_date
  defp get_invoice_date(%SalesInvoice{issue_date: issue_date}), do: issue_date

  defp get_invoice_display_name(%CostInvoice{seller_display_name: name}), do: name
  defp get_invoice_display_name(%SalesInvoice{buyer_display_name: name}), do: name

  defp get_invoice_account_number(%CostInvoice{account_number: acc}), do: acc
  defp get_invoice_account_number(%SalesInvoice{seller_account_number: acc}), do: acc

  defp get_invoice_identifier(%CostInvoice{invoice_identifier: id}), do: id
  defp get_invoice_identifier(%SalesInvoice{invoice_number: id}), do: id

  defp get_transaction_side_name(%CostInvoice{}, %Transaction{creditor_name: name}), do: name
  defp get_transaction_side_name(%SalesInvoice{}, %Transaction{debtor_name: name}), do: name

  defp get_transaction_side_account(%CostInvoice{}, %Transaction{creditor_account: acc}), do: acc
  defp get_transaction_side_account(%SalesInvoice{}, %Transaction{debtor_account: acc}), do: acc

  @spec amount_present_in_remittance_information_unstructured(String.t(), %Decimal{}, String.t()) ::
          float()
  defp amount_present_in_remittance_information_unstructured(
         remittance_information_unstructured,
         amount,
         currency
       ) do
    (String.contains?(remittance_information_unstructured, currency) and
       String.contains?(
         remittance_information_unstructured,
         amount
         |> Decimal.abs()
         |> Decimal.to_float()
         |> trunc()
         |> to_string()
       ))
    |> boolean_to_float()
  end

  defp invoice_identifier_present_in_remittance_information_unstructured(
         remittance_information_unstructured,
         invoice_identifier
       ) do
    String.contains?(
      remittance_information_unstructured,
      invoice_identifier |> normalize_invoice_identifier()
    )
    |> boolean_to_float()
  end

  defp normalize_invoice_identifier(nil), do: "NA"

  defp normalize_invoice_identifier(invoice_identifier) do
    invoice_identifier
    |> String.upcase()
    |> String.replace(~r/[^A-Z0-9\-\/]/, "")
  end

  @spec calculate_difference_in_days(Date.t(), Date.t()) :: integer()
  defp calculate_difference_in_days(due_date, booking_date) do
    Date.diff(booking_date, due_date)
  end

  @spec calculate_relative_amount_difference(%CostInvoice{} | %SalesInvoice{}, %Transaction{}) ::
          float()
  defp calculate_relative_amount_difference(invoice, transaction) do
    # 1. Bring both amounts to PLN
    inv_pln =
      Firmowid.Currencies.normalize_amount_to_pln(
        get_invoice_amount(invoice),
        invoice.currency,
        get_invoice_date(invoice)
      )

    tx_pln =
      Firmowid.Currencies.normalize_amount_to_pln(
        transaction.transaction_amount,
        transaction.transaction_currency,
        transaction.booking_date
      )

    # 2. Work with absolute values (sign irrelevant for *size* of mismatch)
    abs_inv = Decimal.abs(inv_pln)
    abs_tx = Decimal.abs(tx_pln)

    abs_diff = Decimal.sub(abs_tx, abs_inv) |> Decimal.abs()

    # 3. Guard tiny invoices using absolute value
    denom =
      if Decimal.lt?(abs_inv, Decimal.new("0.01")),
        do: Decimal.new("0.01"),
        else: abs_inv

    rel =
      Decimal.div(abs_diff, denom)
      |> Decimal.to_float()

    # 4. Clip outliers just before feeding to the model
    Nx.clip(rel, 0.0, 5.0) |> Nx.to_number()
  end

  defp get_invoice_amount(%Firmowid.CostInvoices.CostInvoice{} = ci), do: ci.total_amount

  defp get_invoice_amount(%Firmowid.SalesInvoices.SalesInvoice{} = si),
    do: Firmowid.SalesInvoices.SalesInvoice.get_gross_value(si)

  @spec calculate_transaction_side_similarity(String.t(), String.t()) :: float()
  defp calculate_transaction_side_similarity(transaction_side_name, seller_display_name) do
    Akin.compare(transaction_side_name, seller_display_name, algorithms: ["jaro_winkler"])
    |> Map.get(:jaro_winkler, 0.0)
  end

  @spec calculate_bank_account_similarity(String.t() | nil, String.t() | nil) :: float()
  defp calculate_bank_account_similarity("", ""), do: calculate_bank_account_similarity(nil, nil)
  defp calculate_bank_account_similarity("", nil), do: calculate_bank_account_similarity(nil, nil)
  defp calculate_bank_account_similarity(nil, ""), do: calculate_bank_account_similarity(nil, nil)

  defp calculate_bank_account_similarity(nil, nil), do: 0.0

  defp calculate_bank_account_similarity(creditor_account, account_number) do
    creditor_account = normalize_iban(creditor_account)
    account_number = normalize_iban(account_number)

    Akin.compare(creditor_account, account_number, algorithms: ["overlap"])
    |> Map.get(:overlap, 0.0)
  end

  @spec normalize_iban(String.t() | nil) :: String.t()
  defp normalize_iban(nil), do: ""

  defp normalize_iban(iban) do
    iban
    |> String.upcase()
    |> String.replace(~r/[^A-Z0-9]/, "")
  end

  @spec calculate_signed_amount_match(%CostInvoice{} | %SalesInvoice{}, %Transaction{}) :: float()
  defp calculate_signed_amount_match(
         %Firmowid.CostInvoices.CostInvoice{} = cost_invoice,
         %Firmowid.Finances.Transaction{} = transaction
       ) do
    inv_amount_pln =
      Firmowid.Currencies.normalize_amount_to_pln(
        get_invoice_amount(cost_invoice),
        cost_invoice.currency,
        get_invoice_date(cost_invoice)
      )

    tx_amount_pln =
      Firmowid.Currencies.normalize_amount_to_pln(
        transaction.transaction_amount,
        transaction.transaction_currency,
        transaction.booking_date
      )

    ratio =
      if Decimal.lt?(Decimal.abs(inv_amount_pln), Decimal.new("0.01")) do
        0.0
      else
        Decimal.div(tx_amount_pln, inv_amount_pln)
        |> Decimal.to_float()
      end

    Nx.clip(ratio, -5.0, 5.0) |> Nx.to_number()
  end

  defp calculate_signed_amount_match(
         %Firmowid.SalesInvoices.SalesInvoice{} = sales_invoice,
         %Firmowid.Finances.Transaction{} = transaction
       ) do
    inv_amount_pln =
      Firmowid.Currencies.normalize_amount_to_pln(
        get_invoice_amount(sales_invoice),
        sales_invoice.currency,
        get_invoice_date(sales_invoice)
      )

    tx_amount_pln =
      Firmowid.Currencies.normalize_amount_to_pln(
        transaction.transaction_amount,
        transaction.transaction_currency,
        transaction.booking_date
      )

    ratio =
      if Decimal.lt?(Decimal.abs(inv_amount_pln), Decimal.new("0.01")) do
        0.0
      else
        Decimal.div(tx_amount_pln, inv_amount_pln)
        |> Decimal.to_float()
      end

    Nx.clip(ratio, -5.0, 5.0) |> Nx.to_number()
  end

  # Returns {le_3, le_7, le_30, gt_30} as booleans
  @spec days_lag_buckets(integer()) :: {boolean(), boolean(), boolean(), boolean()}
  defp days_lag_buckets(days_diff) do
    {
      days_diff <= 3,
      days_diff > 3 and days_diff <= 7,
      days_diff > 7 and days_diff <= 30,
      days_diff > 30
    }
  end

  defp boolean_to_float(bool) do
    if bool, do: 1.0, else: 0.0
  end
end
