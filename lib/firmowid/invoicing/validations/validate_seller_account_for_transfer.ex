defmodule Firmowid.Invoicing.Validations.ValidateSellerAccountForTransfer do
  @moduledoc """
  Requires seller bank account number only for transfer payments.

  For `:cash` and `:card`, account number is optional.

  ## Options

    * `:payment_method_field` — payment method attribute name (default: `:payment_method`)
    * `:seller_account_field` — seller account attribute name (default: `:seller_account_number`)
  """
  use Ash.Resource.Validation
  use Gettext, backend: Firmowid.Gettext

  @impl true
  def validate(changeset, opts, _context) do
    payment_method_field = opts[:payment_method_field] || :payment_method
    seller_account_field = opts[:seller_account_field] || :seller_account_number

    payment_method = Ash.Changeset.get_attribute(changeset, payment_method_field)
    seller_account_number = Ash.Changeset.get_attribute(changeset, seller_account_field)

    case payment_method do
      :transfer ->
        validate_transfer_account(seller_account_number, seller_account_field)

      _other ->
        :ok
    end
  end

  defp validate_transfer_account(value, field) do
    account_number = sanitize(value)

    cond do
      account_number == "" ->
        {:error, field: field, message: gettext_noop("The account number is required for a bank transfer")}

      String.length(account_number) < 10 or String.length(account_number) > 34 ->
        {:error, field: field, message: gettext_noop("The account number must be between 10 and 34 characters")}

      true ->
        :ok
    end
  end

  defp sanitize(nil), do: ""

  defp sanitize(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.replace(~r/[\s-]/u, "")
  end

  defp sanitize(value), do: value |> to_string() |> sanitize()
end
