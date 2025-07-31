defmodule Firmowid.Analysis do
  import Ecto.Query, warn: false
  alias Firmowid.Repo

  alias Firmowid.Analysis.{Tag, TaggedItem}

  @behaviour Bodyguard.Policy

  def authorize(:read, %{role: :admin}, _), do: true
  def authorize(:create, %{role: :admin}, _), do: true
  def authorize(:update, %{role: :admin}, _), do: true
  def authorize(:delete, %{role: :admin}, _), do: true
  def authorize(_, _, _), do: false

  # Tags

  def list_tags do
    Tag
    |> order_by([t], t.name)
    |> Repo.all()
  end

  def get_tag!(id), do: Repo.get!(Tag, id)

  def create_tag(attrs \\ %{}) do
    %Tag{}
    |> Tag.changeset(attrs)
    |> Repo.insert()
  end

  def update_tag(%Tag{} = tag, attrs) do
    tag
    |> Tag.changeset(attrs)
    |> Repo.update()
  end

  def delete_tag(%Tag{} = tag) do
    Repo.delete(tag)
  end

  def change_tag(%Tag{} = tag, attrs \\ %{}) do
    Tag.changeset(tag, attrs)
  end

  # Tagging

  def tag_entity(entity_type, entity_id, tag_id) do
    %TaggedItem{}
    |> TaggedItem.changeset(%{
      entity_type: entity_type,
      entity_id: entity_id,
      tag_id: tag_id
    })
    |> Repo.insert()
  end

  def untag_entity(entity_type, entity_id, tag_id) do
    case Repo.get_by(TaggedItem, entity_type: entity_type, entity_id: entity_id, tag_id: tag_id) do
      nil -> {:error, :not_found}
      tagged_item -> Repo.delete(tagged_item)
    end
  end

  def get_entity_tags(entity_type, entity_id) do
    TaggedItem
    |> where([ti], ti.entity_type == ^entity_type and ti.entity_id == ^entity_id)
    |> preload(:tag)
    |> Repo.all()
    |> Enum.map(& &1.tag)
  end

  def list_tagged_entities(tag_id) do
    TaggedItem
    |> where([ti], ti.tag_id == ^tag_id)
    |> preload(:tag)
    |> Repo.all()
  end

  def get_entity_ids_by_tag(tag_id, entity_type) do
    TaggedItem
    |> where([ti], ti.tag_id == ^tag_id and ti.entity_type == ^entity_type)
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

  def get_organization_totals(date_from \\ nil, date_to \\ nil, tag_id \\ nil) do
    # Check if this is the special "całość" tag (show all data)
    calosci_tag = get_calosci_tag()

    {sales_total, cost_total, transaction_income, transaction_expenses} =
      if tag_id && tag_id != calosci_tag.id do
        # Get entity IDs for the specified tag
        sales_invoice_ids = get_sales_invoice_ids_by_tag(tag_id)
        cost_invoice_ids = get_cost_invoice_ids_by_tag(tag_id)
        transaction_ids = get_transaction_ids_by_tag(tag_id)

        # Get entities and calculate totals in Analysis context
        sales_invoices =
          Firmowid.SalesInvoices.list_sales_invoices_by_ids(sales_invoice_ids, date_from, date_to)

        cost_invoices =
          Firmowid.CostInvoices.list_cost_invoices_by_ids(cost_invoice_ids, date_from, date_to)

        transactions =
          Firmowid.Finances.list_transactions_by_ids(transaction_ids, date_from, date_to)

        # Calculate totals using existing schema functions and Analysis context summing
        sales_total = calculate_sales_invoices_total(sales_invoices)
        cost_total = calculate_cost_invoices_total(cost_invoices)
        transaction_income = calculate_transaction_income_total(transactions)
        transaction_expenses = calculate_transaction_expenses_total(transactions)

        {sales_total, cost_total, transaction_income, transaction_expenses}
      else
        # Get all data without tag filtering (for "całość" tag or no tag specified)
        sales_invoices = Firmowid.SalesInvoices.list_sales_invoices(date_from, date_to)
        cost_invoices = Firmowid.CostInvoices.list_cost_invoices(date_from, date_to)
        transactions = Firmowid.Finances.list_transactions(date_from, date_to)

        # Calculate totals using existing schema functions and Analysis context summing
        sales_total = calculate_sales_invoices_total(sales_invoices)
        cost_total = calculate_cost_invoices_total(cost_invoices)
        transaction_income = calculate_transaction_income_total(transactions)
        transaction_expenses = calculate_transaction_expenses_total(transactions)

        {sales_total, cost_total, transaction_income, transaction_expenses}
      end

    total_income = Decimal.add(sales_total, transaction_income)
    total_expenses = Decimal.add(cost_total, transaction_expenses)
    net_profit = Decimal.sub(total_income, total_expenses)

    %{
      total_income: total_income,
      total_expenses: total_expenses,
      net_profit: net_profit
    }
  end

  # Private calculation functions that sum up entities using their schema functions

  defp calculate_sales_invoices_total(sales_invoices) do
    sales_invoices
    |> Enum.reduce(Decimal.new(0), fn invoice, acc ->
      # Use the existing get_gross_value function from SalesInvoice schema
      invoice_total = Firmowid.SalesInvoices.SalesInvoice.get_gross_value(invoice)
      Decimal.add(acc, invoice_total)
    end)
  end

  defp calculate_cost_invoices_total(cost_invoices) do
    cost_invoices
    |> Enum.reduce(Decimal.new(0), fn invoice, acc ->
      Decimal.add(acc, invoice.total_amount)
    end)
  end

  defp calculate_transaction_income_total(transactions) do
    transactions
    |> Enum.filter(&Decimal.positive?(&1.transaction_amount))
    |> Enum.reduce(Decimal.new(0), fn transaction, acc ->
      Decimal.add(acc, transaction.transaction_amount)
    end)
  end

  defp calculate_transaction_expenses_total(transactions) do
    transactions
    |> Enum.filter(&Decimal.negative?(&1.transaction_amount))
    |> Enum.reduce(Decimal.new(0), fn transaction, acc ->
      Decimal.add(acc, Decimal.abs(transaction.transaction_amount))
    end)
  end

  def get_firma_tag do
    case Repo.get_by(Tag, name: "firma") do
      nil ->
        {:ok, tag} = create_tag(%{name: "firma", color: "#3B82F6"})
        tag

      tag ->
        tag
    end
  end

  def get_calosci_tag do
    case Repo.get_by(Tag, name: "całość") do
      nil ->
        {:ok, tag} = create_tag(%{name: "całość", color: "#10B981"})
        tag

      tag ->
        tag
    end
  end

  def ensure_firma_tag do
    case Repo.get_by(Tag, name: "firma") do
      nil ->
        create_tag(%{name: "firma", color: "#3B82F6"})

      tag ->
        {:ok, tag}
    end
  end

  def ensure_calosci_tag do
    case Repo.get_by(Tag, name: "całość") do
      nil ->
        create_tag(%{name: "całość", color: "#10B981"})

      tag ->
        {:ok, tag}
    end
  end
end
