defmodule Firmowid.Invoicing.Matching.Assistant.Input do
  alias Firmowid.CostInvoices.CostInvoice
  alias Firmowid.Finances.Transaction

  def cost_invoice_input(invoice = %CostInvoice{}, options \\ []) do
    heading_level = Keyword.get(options, :heading_level, 1)

    """
    #{"#" |> String.duplicate(heading_level)} Faktura kosztowa #{invoice.invoice_identifier}

    > **Opis:** #{invoice.description}

    - **Skrócona nazwa sprzedawcy:** #{invoice.seller_display_name}
    - **Pełna nazwa sprzedawcy:** #{invoice.seller}
    - **Adres sprzedawcy:** #{invoice.seller_address}
    - **Numer konta sprzedawcy:** #{invoice.account_number}
    - **Data wystawienia:** #{invoice.issue_date}
    - **Data płatności:** #{invoice.due_date}
    - **Kwota:** #{invoice.total_amount}
    - **Waluta:** #{invoice.currency}

    > UUID: `#{invoice.id}`
    """
  end

  def transaction_input(transaction = %Transaction{}, options \\ []) do
    heading_level = Keyword.get(options, :heading_level, 1)

    """
    #{"#" |> String.duplicate(heading_level)} Transakcja

    > **Dodatkowe informacje z banku:** #{transaction.remittance_information_unstructured}

    - **Data księgowania:** #{transaction.booking_date}
    - **Data wartości:** #{transaction.value_date}
    - **Kwota:** #{transaction.transaction_amount}
    - **Waluta:** #{transaction.transaction_currency}
    - **Odbiorca:** #{transaction.debtor_name}
    - **Numer konta odbiorcy:** #{transaction.debtor_account}
    - **Nadawca:** #{transaction.creditor_name}
    - **Numer konta nadawcy:** #{transaction.creditor_account}
    - **Powiązane faktury kosztowe:** #{Enum.map(transaction.cost_invoices_transactions, & &1.id) |> Enum.join(", ")}

    > UUID: `#{transaction.id}`
    """
  end
end
