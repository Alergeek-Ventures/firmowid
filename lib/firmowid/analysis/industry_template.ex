defmodule Firmowid.Analysis.IndustryTemplate do
  @moduledoc """
  Industry templates for financial analysis, kept as data.

  Every template shares one cost skeleton modelled on the Polish cost-by-nature
  layout (układ rodzajowy), ordered by what matters most in that industry, and
  names its own revenue channels. The organization chooses its industry;
  category descriptions guide the classifier.
  """

  @type industry :: :services | :gastronomy | :retail
  @type side :: :income | :expenses
  @type category :: atom()

  @industries [:services, :gastronomy, :retail]

  @expense_categories [
    :goods,
    :subcontractors,
    :payroll,
    :premises,
    :software,
    :marketing,
    :services,
    :fees,
    :transport,
    :equipment,
    :taxes,
    :other
  ]

  @expense_order %{
    services: [:payroll, :subcontractors, :software, :premises, :marketing, :services],
    gastronomy: [:goods, :payroll, :premises, :fees, :marketing, :services],
    retail: [:goods, :payroll, :premises, :fees, :marketing, :transport]
  }

  @income_categories %{
    services: [:sales, :other_income],
    gastronomy: [:on_site, :delivery, :catering, :other_income],
    retail: [:store, :online, :sales, :other_income]
  }

  # Costs an owner in the industry watches as a share of income.
  @key_costs %{
    services: [people: [:payroll, :subcontractors], software: [:software], premises: [:premises]],
    gastronomy: [food: [:goods], labour: [:payroll], premises: [:premises]],
    retail: [goods: [:goods], labour: [:payroll], premises: [:premises]]
  }

  # What each category covers, for the classifier choosing one from an entry's description.
  @descriptions %{
    goods: "Goods for resale, raw materials and ingredients",
    subcontractors: "Subcontractors and freelancers doing the company's core work",
    payroll: "Salaries, social security contributions and other employee costs",
    premises: "Rent, utilities, energy, internet and phone for the premises",
    software: "Software subscriptions, hosting and IT tools",
    marketing: "Advertising, promotion and marketing services",
    services: "Accounting, legal, cleaning and other external business services",
    fees: "Bank, card terminal and platform fees and commissions",
    transport: "Fuel, vehicles, travel, shipping and couriers",
    equipment: "Equipment, tools, furniture and office supplies",
    taxes: "Taxes paid to tax authorities",
    other: "Costs fitting no other category",
    sales: "Sales of the company's products or services",
    on_site: "Sales at the venue: card terminal settlements and cash",
    delivery: "Sales through food delivery platforms",
    catering: "Catering and events ordered by businesses",
    store: "Sales in a physical store: card terminal settlements and cash",
    online: "Sales through an online store or marketplace",
    other_income: "Grants, subsidies, refunds, interest and other income"
  }

  @doc "Lists the supported industries."
  @spec industries() :: [industry()]
  def industries, do: @industries

  @doc "Lists every category of a side across all industries."
  @spec all_categories(side()) :: [category()]
  def all_categories(:expenses), do: @expense_categories

  def all_categories(:income), do: @income_categories |> Map.values() |> List.flatten() |> Enum.uniq()

  @doc "Lists an industry's categories of one side, most important first."
  @spec categories(industry(), side()) :: [category()]
  def categories(industry, :expenses) do
    order = Map.fetch!(@expense_order, industry)
    order ++ (@expense_categories -- order)
  end

  def categories(industry, :income), do: Map.fetch!(@income_categories, industry)

  @doc "Lists the industry's key costs, each with the expense categories it sums."
  @spec key_costs(industry()) :: [{atom(), [category()]}]
  def key_costs(industry), do: Map.fetch!(@key_costs, industry)

  @doc "Describes what a category covers."
  @spec describe(category()) :: String.t()
  def describe(category), do: Map.fetch!(@descriptions, category)
end
