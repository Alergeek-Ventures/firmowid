defmodule Firmowid.Ash.Analysis.IndustryTemplate do
  @moduledoc """
  Industry templates for financial analysis, kept as data.

  Every template shares one cost skeleton modelled on the Polish cost-by-nature
  layout (układ rodzajowy), ordered by what matters most in that industry, and
  names its own revenue channels. Templates also carry hints that turn
  counterparty names and invoice lines into category suggestions.
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

  # Keywords match inside normalized text; spaces around one require a whole word.
  @name_hints [
    {["zakład ubezpieczeń społecznych", " zus "], :expenses, :payroll},
    {["urząd skarbowy", "izba administracji skarbowej"], :expenses, :taxes},
    {[
       "nieruchomości",
       "wspólnota mieszkaniowa",
       "spółdzielnia mieszkaniowa",
       " regus ",
       "wework",
       "cowork"
     ], :expenses, :premises},
    {[
       " pge ",
       "tauron",
       " enea ",
       "energa",
       "pgnig",
       "innogy",
       "veolia",
       "wodociąg",
       " mpwik ",
       "fortum"
     ], :expenses, :premises},
    {["orange", "t-mobile", "polkomtel", " play ", "netia", " upc ", "vectra", " inea "], :expenses, :premises},
    {[
       "github",
       "microsoft",
       "atlassian",
       "slack",
       "notion",
       "openai",
       "anthropic",
       "figma",
       "jetbrains",
       "adobe",
       "hetzner",
       " ovh ",
       "cloudflare",
       "vercel",
       "digitalocean",
       "amazon web services",
       "google cloud",
       "google workspace"
     ], :expenses, :software},
    {["meta platforms", "facebook", "linkedin", "tiktok", "google ads"], :expenses, :marketing},
    {["biuro rachunkowe", "księgow", "kancelaria", "notariusz", "radca prawny"], :expenses, :services},
    {[
       " orlen ",
       " bp ",
       " shell ",
       "circle k",
       " lotos ",
       " moya ",
       " amic ",
       " pkp ",
       " dpd ",
       "inpost",
       " dhl ",
       " gls ",
       "poczta polska",
       "fedex"
     ], :expenses, :transport},
    {[
       "fiserv",
       "polcard",
       "eservice",
       "przelewy24",
       " payu ",
       "stripe",
       "sumup",
       " tpay ",
       "adyen",
       " bank "
     ], :expenses, :fees},
    {[
       " apple ",
       " dell ",
       " lenovo ",
       "allegro",
       " ikea ",
       "media markt",
       "x-kom",
       "komputronik",
       "leroy merlin",
       "castorama"
     ], :expenses, :equipment},
    {[" makro ", "selgros", "eurocash", "hurtowni"], :expenses, :goods}
  ]

  @delivery_platforms ["glovo", "takeaway", "pyszne", " wolt ", "uber eats", "bolt food"]
  @card_acquirers ["fiserv", "polcard", "eservice", "sumup", "adyen"]

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
       ], :expenses, :goods},
      {@delivery_platforms, :expenses, :fees},
      {@delivery_platforms, :income, :delivery},
      {@card_acquirers, :income, :on_site}
    ],
    retail: [
      {["kwiat", "giełd", "flor", "ogrodnic", "szkółk"], :expenses, :goods},
      {["allegro", "shopify", "etsy", "amazon", "przelewy24", " payu "], :income, :online},
      {@card_acquirers, :income, :store}
    ]
  }

  # Invoice line names, typically from KSeF, that point to a cost category.
  @line_hints [
    {[
       " kawa ",
       " kawy ",
       "mleko",
       "cukier",
       "syrop",
       "kubk",
       "pieczyw",
       "croissant",
       "chleb",
       "warzyw",
       "owoc",
       "mięs",
       "kwiat",
       " róż",
       "tulipan",
       "towar",
       "surowc"
     ], :goods},
    {["wynagrodzeni", "pensj", "premi", "składk"], :payroll},
    {[
       "czynsz",
       "najem",
       "energi",
       "paliwo gazowe",
       " gaz ",
       " woda ",
       "ścieki",
       "internet",
       "telefon"
     ], :premises},
    {[
       "licencj",
       "subskrypc",
       "hosting",
       "serwer",
       "chmur",
       "oprogramowani",
       "asystent ai",
       "stanowisk",
       " ci/cd "
     ], :software},
    {["reklam", "kampani", "marketing", "promocj"], :marketing},
    {["księgow", "doradztw", "prawn", "sprzątani"], :services},
    {["prowizj", "terminal", "opłata transakcyjn", "prowadzenie rachunku", "przewalutowani"], :fees},
    {["paliw", "transport", "przesyłk", "kurier"], :transport},
    {["programist", "wdrożeni", "usługi informatyczn", "konsultacj", "projekt graficzny"], :subcontractors},
    {[
       "młynek",
       "ekspres",
       "mebl",
       "krzes",
       " stół",
       "laptop",
       "macbook",
       "monitor",
       "wyposażeni",
       "biurow",
       "eksploatacyjn"
     ], :equipment}
  ]

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

  @doc "Returns the category for income without a better suggestion."
  @spec default_income(industry()) :: category()
  def default_income(:services), do: :sales
  def default_income(:gastronomy), do: :catering
  def default_income(:retail), do: :sales

  @doc "Suggests a category from a counterparty name, preferring industry hints."
  @spec name_category(industry(), side(), String.t() | nil) :: category() | nil
  def name_category(_industry, _side, nil), do: nil

  def name_category(industry, side, name) do
    name = normalize(name)

    Enum.find_value(Map.fetch!(@industry_name_hints, industry) ++ @name_hints, fn {keywords, hint_side, category} ->
      if hint_side == side and String.contains?(name, keywords), do: category
    end)
  end

  @doc "Suggests a cost category from one invoice line name."
  @spec line_category(String.t() | nil) :: category() | nil
  def line_category(nil), do: nil

  def line_category(name) do
    name = normalize(name)

    Enum.find_value(@line_hints, fn {keywords, category} ->
      if String.contains?(name, keywords), do: category
    end)
  end

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

            if Enum.any?(hints, fn {keywords, hint_side, _} ->
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
