defmodule Firmowid.Invoicing.Validations.ValidateLineDiscountTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias Ash.Error.Changes.InvalidAttribute
  alias Firmowid.Invoicing.SalesInvoiceItem
  alias Firmowid.Invoicing.WizardState.Item

  for resource <- [SalesInvoiceItem, Item] do
    @resource resource

    test "#{inspect(resource)} rejects a discount outside its line value before discount" do
      changeset =
        item_changeset(@resource, %{"quantity" => "0", "unit_price" => "100", "discount" => "10"})

      assert Enum.any?(changeset.errors, &match?(%InvalidAttribute{field: :discount}, &1))
    end
  end

  test "allows a full discount on a removed line and a sign-preserving discount on a negative line" do
    assert item_changeset(SalesInvoiceItem, %{
             "quantity" => "0",
             "unit_price" => "100",
             "discount" => "0"
           }).valid?

    assert item_changeset(SalesInvoiceItem, %{
             "quantity" => "1",
             "unit_price" => "-100",
             "discount" => "-10"
           }).valid?
  end

  defp item_changeset(resource, overrides) do
    attrs =
      %{
        "index" => "0",
        "name" => "Line",
        "quantity" => "1",
        "unit" => "szt.",
        "unit_price" => "100",
        "discount" => nil,
        "vat_rate" => "23"
      }
      |> Map.merge(overrides)
      |> then(&if resource == Item, do: Map.put(&1, "wizard_state_id", Ash.UUID.generate()), else: &1)

    Ash.Changeset.for_create(resource, :create, attrs, actor: %{}, authorize?: false)
  end
end
