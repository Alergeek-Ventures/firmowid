defmodule Firmowid.Invoicing.Validations.CompleteInvoice do
  @moduledoc "Final invoice validation shared by issuance, complete saved drafts, and previews."
  use Ash.Resource.Validation
  use Gettext, backend: Firmowid.Gettext

  alias Ash.Error.Changes.InvalidAttribute
  alias Firmowid.Invoicing.Validations.ValidateBuyerIdRequired
  alias Firmowid.Invoicing.Validations.ValidateItemsNotEmpty
  alias Firmowid.Invoicing.Validations.ValidateSellerAccountForTransfer

  @required_fields [
    :buyer_address,
    :buyer_country,
    :currency,
    :issue_date,
    :sale_date,
    :due_date,
    :payment_method
  ]
  @currencies Enum.map(Money.known_currencies(), &to_string/1)

  @doc "Checks final identity and payment completeness without requiring an invoice number."
  @spec validate(Ash.Changeset.t(), keyword(), Ash.Resource.Validation.Context.t()) ::
          :ok | {:error, [Exception.t()]}
  @impl true
  def validate(changeset, _opts, context) do
    required = Enum.map(@required_fields, &{&1, gettext_noop("This field is required.")})

    errors =
      Enum.flat_map(seller_requirements() ++ required, fn {field, message} ->
        if blank?(Ash.Changeset.get_attribute(changeset, field)) do
          [InvalidAttribute.exception(field: field, message: message)]
        else
          []
        end
      end)

    errors = errors ++ currency_errors(changeset) ++ business_buyer_errors(changeset)

    errors =
      Enum.reduce(
        validations(changeset),
        errors,
        fn {validation, opts}, errors ->
          case validation.validate(changeset, opts, context) do
            :ok -> errors
            {:error, error} -> errors ++ [InvalidAttribute.exception(error)]
          end
        end
      )

    case errors do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  # Seller details are copied from the organization, so the fix belongs in its settings, not the invoice form.
  defp seller_requirements do
    [
      seller_nip: gettext_noop("Complete the company NIP in the organization settings."),
      seller_display_name: gettext_noop("Complete the company name in the organization settings."),
      seller_address: gettext_noop("Complete the company address in the organization settings.")
    ]
  end

  defp validations(changeset) do
    validations = [{ValidateBuyerIdRequired, []}, {ValidateSellerAccountForTransfer, []}]

    if changeset.action_type == :create or
         not is_nil(Ash.Changeset.get_argument(changeset, :sales_invoice_items)) do
      validations ++ [{ValidateItemsNotEmpty, [field: :sales_invoice_items, source: :argument]}]
    else
      validations
    end
  end

  defp currency_errors(changeset) do
    currency = Ash.Changeset.get_attribute(changeset, :currency)

    if blank?(currency) or currency in @currencies do
      []
    else
      [
        InvalidAttribute.exception(
          field: :currency,
          message: gettext_noop("Choose a valid three-letter currency code.")
        )
      ]
    end
  end

  defp business_buyer_errors(%{context: %{shared: %{business_buyers_only?: true}}} = changeset) do
    company? = Ash.Changeset.get_attribute(changeset, :buyer_type) == :company
    tax_id = Ash.Changeset.get_attribute(changeset, :buyer_id)

    if company? and not blank?(tax_id) do
      []
    else
      [
        InvalidAttribute.exception(
          field: if(company?, do: :buyer_id, else: :buyer_type),
          message:
            gettext_noop(
              "Only business buyers with a tax ID are supported here. Use the Firmowid web app for invoices to private individuals."
            )
        )
      ]
    end
  end

  defp business_buyer_errors(_changeset), do: []

  defp blank?(nil), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_value), do: false
end
