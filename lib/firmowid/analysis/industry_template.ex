defmodule Firmowid.Analysis.IndustryTemplate do
  @moduledoc """
  Industry templates for financial analysis, kept as data.

  Every template shares one cost skeleton modelled on the Polish cost-by-nature
  layout (układ rodzajowy), ordered by what matters most in that industry, and
  names its own revenue channels. Counterparty name hints of industry-specific
  businesses infer the industry; category descriptions guide the classifier.
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

  # Keywords match inside normalized text; spaces around one require a whole word.
  @delivery_platforms ["glovo", "takeaway", "pyszne", " wolt ", "uber eats", "bolt food"]
  @card_acquirers ["fiserv", "polcard", "eservice", "sumup", "adyen"]

  # Counterparties typical of one industry, by the side they appear on.
  @industry_name_hints %{
    services: [],
    gastronomy: [
      {[
         "palarni",
         "piekarni",
         "mleczar",
         "cukierni",
         "browar",
         "warzyw",
         "owoc",
         " lidl ",
         "biedronka",
         "kaufland",
         "auchan",
         "carrefour"
       ], :expenses},
      {@delivery_platforms, :expenses},
      {@delivery_platforms, :income},
      {@card_acquirers, :income}
    ],
    retail: [
      {["kwiat", "giełd", "flor", "ogrodnic", "szkółk"], :expenses},
      {["allegro", "shopify", "etsy", "amazon", "przelewy24", " payu "], :income},
      {@card_acquirers, :income}
    ]
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

  @doc """
  Infers the industry from counterparty names weighted by amount.

  Only industry-specific hints count; without any, the business is treated as services.
  """
  @spec infer([{side(), String.t() | nil, Decimal.t()}]) :: industry()
  def infer(counterparties) do
    scores =
      for industry <- [:gastronomy, :retail], into: %{} do
        hints = Map.fetch!(@industry_name_hints, industry)

        score =
          Enum.reduce(counterparties, Decimal.new(0), fn {side, name, amount}, sum ->
            name = normalize(name || "")

            if Enum.any?(hints, fn {keywords, hint_side} ->
                 hint_side == side and String.contains?(name, keywords)
               end),
               do: Decimal.add(sum, amount),
               else: sum
          end)

        {industry, score}
      end

    {industry, score} = Enum.max_by(scores, &elem(&1, 1), Decimal)
    if Decimal.positive?(score), do: industry, else: :services
  end

  @doc "Lowercases text and pads its words with single spaces for keyword matching."
  @spec normalize(String.t()) :: String.t()
  def normalize(text) do
    words = text |> String.downcase() |> String.split(~r/[^\p{L}\p{N}\-]+/u, trim: true)
    " " <> Enum.join(words, " ") <> " "
  end
end
