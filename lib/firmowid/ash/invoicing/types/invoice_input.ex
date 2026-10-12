defmodule Firmowid.Ash.Invoicing.Types.InvoiceInput do
  @moduledoc "Editable invoice input. Seller identity is derived from the scoped organization."
  use Ash.Type.NewType,
    subtype_of: :map,
    constraints: [
      preserve_nil_values?: true,
      fields: [
        invoice_type: [type: :atom, constraints: [one_of: [:poland, :foreign]]],
        invoice_number: [type: :string],
        issue_date: [type: :date],
        sale_date: [type: :date],
        due_date: [type: :date],
        payment_method: [
          type: :atom,
          constraints: [one_of: [:cash, :card, :voucher, :check, :credit, :transfer, :mobile]]
        ],
        currency: [type: :string],
        is_cash_account: [type: :boolean],
        is_reverse_charge: [type: :boolean],
        skip_invoicing: [type: :boolean],
        counterparty_id: [type: :uuid_v7],
        seller_account_number: [type: :string],
        vat_exemption_type: [
          type: :atom,
          constraints: [one_of: Firmowid.Ash.Invoicing.VatExemption.valid_types()]
        ],
        vat_exemption_basis: [type: :string],
        buyer_type: [type: :atom, constraints: [one_of: [:company, :individual]]],
        buyer_id: [type: :string],
        buyer_full_name: [type: :string],
        buyer_given_name: [type: :string],
        buyer_surname: [type: :string],
        buyer_pesel: [type: :string],
        buyer_display_name: [type: :string],
        buyer_address: [type: :string],
        buyer_country: [type: :string],
        buyer_is_different_mail_address: [type: :boolean],
        buyer_mail_address: [type: :string],
        buyer_mail_country: [type: :string],
        buyer_email: [type: :string],
        buyer_phone: [type: :string],
        buyer_description: [type: :string],
        should_send_emails: [type: :boolean],
        invoice_note: [type: :string],
        internal_note: [type: :string, constraints: [max_length: 10_000]],
        correction_reason: [type: :string, constraints: [max_length: 256]],
        sales_invoice_items: [type: {:array, Firmowid.Ash.Invoicing.Types.InvoiceItemInput}]
      ]
    ]
end
