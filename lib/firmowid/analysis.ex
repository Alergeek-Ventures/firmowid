defmodule Firmowid.Analysis do
  @moduledoc false
  @behaviour Bodyguard.Policy

  import Ecto.Query, warn: false

  alias Firmowid.Analysis.EntityTag
  alias Firmowid.Analysis.TagDefinition
  alias Firmowid.CostInvoices
  alias Firmowid.Currencies
  alias Firmowid.Finances
  alias Firmowid.Repo
  alias Firmowid.SalesInvoices

  def authorize(:read, %{role: :admin}, _), do: true
  def authorize(:create, %{role: :admin}, _), do: true
  def authorize(:update, %{role: :admin}, _), do: true
  def authorize(:delete, %{role: :admin}, _), do: true
  def authorize(_, _, _), do: false

  # CRUD - tags and tagged items

  def list_tag_definitions do
    TagDefinition
    |> order_by([t], t.name)
    |> Repo.all()
  end

  def get_tag_definition!(id), do: Repo.get!(TagDefinition, id)

  def create_tag_definition(attrs \\ %{}) do
    %TagDefinition{}
    |> TagDefinition.changeset(attrs)
    |> Repo.insert()
  end

  def update_tag_definition(%TagDefinition{} = tag, attrs) do
    tag
    |> TagDefinition.changeset(attrs)
    |> Repo.update()
  end

  def delete_tag_definition(%TagDefinition{} = tag) do
    Repo.delete(tag)
  end

  def change_tag_definition(%TagDefinition{} = tag, attrs \\ %{}) do
    TagDefinition.changeset(tag, attrs)
  end

  # Tagging

  def tag_entity(entity_type, entity_id, tag_id) do
    %EntityTag{}
    |> EntityTag.changeset(%{
      entity_type: entity_type,
      entity_id: entity_id,
      tag_definition_id: tag_id
    })
    |> Repo.insert()
  end

  def untag_entity(entity_type, entity_id, tag_id) do
    case Repo.get_by(EntityTag, entity_type: entity_type, entity_id: entity_id, tag_definition_id: tag_id) do
      nil -> {:error, :not_found}
      tagged_item -> Repo.delete(tagged_item)
    end
  end

  def get_entity_tags(entity_type, entity_id) do
    EntityTag
    |> where([ti], ti.entity_type == ^entity_type and ti.entity_id == ^entity_id)
    |> preload(:tag_definition)
    |> Repo.all()
    |> Enum.map(& &1.tag_definition)
  end

  def list_tagged_entities(tag_id) do
    EntityTag
    |> where([ti], ti.tag_definition_id == ^tag_id)
    |> preload(:tag_definition)
    |> Repo.all()
  end

  def get_entity_ids_by_tag(tag_id, entity_type) do
    EntityTag
    |> where([ti], ti.tag_definition_id == ^tag_id and ti.entity_type == ^entity_type)
    |> select([ti], ti.entity_id)
    |> Repo.all()
  end

  def get_sales_invoice_ids_by_tag(tag_id) do
    get_entity_ids_by_tag(tag_id, "sales_invoice")
  end

  def get_cost_invoice_ids_by_tag(tag_id) do
    get_entity_ids_by_tag(tag_id, "cost_invoice")
  end

  def get_transaction_ids_by_tag(tag_id) do
    get_entity_ids_by_tag(tag_id, "transaction")
  end

  # Organization totals calculation

  def get_organization_totals(date_from, date_to, tag_id) do
    # get all invoices and transactions for the specified date range
    sales_invoices = SalesInvoices.list_sales_invoices(date_from, date_to)
    cost_invoices = CostInvoices.list_cost_invoices(date_from, date_to)
    transactions = Finances.list_transactions_with_skipped_invoicing(date_from, date_to)

    %{income: income, expenses: expenses} =
      Enum.reduce(
        sales_invoices ++ cost_invoices ++ transactions,
        %{income: Decimal.new(0), expenses: Decimal.new(0)},
        fn entity, acc ->
          {amount, currency} = get_amount_and_currency(entity)
          normalized_amount = Currencies.normalize_amount_to_pln(amount, currency, Date.utc_today())

          if Decimal.negative?(normalized_amount) do
            Map.update!(acc, :expenses, &Decimal.add(&1, normalized_amount))
          else
            Map.update!(acc, :income, &Decimal.add(&1, normalized_amount))
          end
        end
      )

    %{
      total_income: income,
      total_expenses: expenses,
      net_profit: Decimal.add(income, expenses),
      transactions: transactions,
      sales_invoices: sales_invoices,
      cost_invoices: cost_invoices
    }
  end

  defp get_amount_and_currency(%SalesInvoices.SalesInvoice{} = entity) do
    value =
      entity
      |> SalesInvoices.SalesInvoice.get_gross_value()
      |> Decimal.abs()

    {value, entity.currency}
  end

  defp get_amount_and_currency(%CostInvoices.CostInvoice{} = entity) do
    value = entity.total_amount |> Decimal.abs() |> Decimal.mult(Decimal.new("-1"))
    {value, entity.currency}
  end

  defp get_amount_and_currency(%Finances.Transaction{} = entity) do
    {entity.transaction_amount, entity.transaction_currency}
  end
end
