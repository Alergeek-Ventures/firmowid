defmodule Firmowid.Test.Support.InvoicingCopyAssertions do
  @moduledoc """
  Shared assertions for sales-invoice copy fidelity tests.
  """

  import ExUnit.Assertions

  @preserved_fields [
    :counterparty_id,
    :buyer_type,
    :buyer_id,
    :buyer_full_name,
    :buyer_given_name,
    :buyer_surname,
    :buyer_pesel,
    :buyer_display_name,
    :buyer_address,
    :buyer_country,
    :buyer_email,
    :buyer_phone,
    :buyer_description,
    :invoice_type,
    :is_reverse_charge,
    :currency,
    :payment_method,
    :invoice_note,
    :internal_note
  ]

  @item_fields [:index, :name, :quantity, :unit, :unit_price, :vat_rate]

  @doc """
  Asserts that the copied invoice or draft preserves all business fields that
  must survive the copy flow unchanged.
  """
  @spec assert_preserved_fields!(struct(), struct()) :: true
  def assert_preserved_fields!(source, copy) do
    Enum.each(@preserved_fields, fn field ->
      assert Map.get(copy, field) == Map.get(source, field),
             "expected #{inspect(field)} to be preserved during copy"
    end)

    true
  end

  @doc """
  Asserts that copied drafts do not inherit sale and due dates.
  """
  @spec assert_cleared_dates!(struct()) :: true
  def assert_cleared_dates!(copy) do
    assert is_nil(copy.sale_date)
    assert is_nil(copy.due_date)
    true
  end

  @doc """
  Asserts that the copied draft or invoice uses the expected derived seller
  account number.
  """
  @spec assert_derived_seller_account!(struct(), String.t() | nil) :: true
  def assert_derived_seller_account!(copy, expected_iban) do
    assert Map.get(copy, :seller_account_number) == expected_iban
    true
  end

  @doc """
  Asserts that copied line items match the source items exactly for the fields
  that determine invoicing semantics.
  """
  @spec assert_line_items_match!([struct()], [struct()]) :: true
  def assert_line_items_match!(source_items, copied_items) do
    assert Enum.map(copied_items, &Map.take(&1, @item_fields)) ==
             Enum.map(source_items, &Map.take(&1, @item_fields))

    true
  end
end
