# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Firmowid.Seeds.Cafe do
  @moduledoc """
  Seeds a second, non-project business: the café "Kawiarnia Ziarno" in Kraków.

  The café has no projects and no analysis tags, so its financial analysis
  starts fully unclassified. Data covers the last ten months up to today
  (never future dates): weekly card acquirer payouts, delivery platform
  payouts and catering sales invoices on the income side; supplier cost
  invoices with KSeF-like line items, plus ZUS, taxes, salaries and card
  payments as standalone transactions on the expense side.

  Runnable standalone (after loading `helpers.exs`) and a no-op when the
  café organization already exists.
  """

  alias Firmowid.Ash.Core.Organization, as: CoreOrganization
  alias Firmowid.Ash.Core.User, as: CoreUser
  alias Firmowid.Seeds.Helpers

  require Ash.Query

  @nip "6770012344"
  @org_name "Kawiarnia Ziarno"
  @address "ul. Józefa 12/1, 31-056 Kraków"
  @iban "PL60114020040000300212345678"
  @months_back 10

  # Café traffic by calendar month: winter is slow, summer is busy.
  @seasonality %{
    1 => 0.84,
    2 => 0.88,
    3 => 0.95,
    4 => 1.0,
    5 => 1.05,
    6 => 1.1,
    7 => 1.12,
    8 => 1.08,
    9 => 1.0,
    10 => 0.98,
    11 => 0.9,
    12 => 1.0
  }

  @vendors %{
    makro: {"Makro Cash and Carry Polska S.A.", "Makro", "ul. Kamieńskiego 11, 30-644 Kraków"},
    coffeelab: {"Palarnia Kawy Coffeelab Sp. z o.o.", "Coffeelab", "ul. Zabłocie 27, 30-701 Kraków"},
    bakery: {"Piekarnia Mojego Taty Sp. z o.o.", "Piekarnia Mojego Taty", "ul. Starowiślna 44, 31-038 Kraków"},
    rent: {"Nieruchomości Kazimierz Sp. z o.o.", "Nieruchomości Kazimierz", "ul. Szeroka 8, 31-053 Kraków"},
    pge: {"PGE Obrót S.A.", "PGE", "ul. 8 Marca 6, 35-959 Rzeszów"},
    gas: {"PGNiG Obrót Detaliczny Sp. z o.o.", "PGNiG", "ul. Marcina Kasprzaka 25, 01-224 Warszawa"},
    orange: {"Orange Polska S.A.", "Orange", "Al. Jerozolimskie 160, 02-326 Warszawa"},
    meta: {"Meta Platforms Ireland Ltd.", "Meta", "4 Grand Canal Square, Dublin 2, Irlandia"},
    bilans: {"Biuro Rachunkowe Bilans Sp. z o.o.", "Biuro Bilans", "ul. Dietla 55/3, 31-039 Kraków"},
    glovo: {"Glovoapp Poland Sp. z o.o.", "Glovo", "ul. Prosta 70, 00-838 Warszawa"},
    takeaway: {"Takeaway.com Polska Sp. z o.o.", "Pyszne.pl", "ul. Domaniewska 39, 02-672 Warszawa"},
    fiserv: {"Fiserv Polska S.A.", "Fiserv", "ul. Prosta 68, 00-838 Warszawa"},
    allegro: {"Allegro.pl Sp. z o.o.", "Allegro", "ul. Wierzbięcice 1, 61-558 Poznań"}
  }

  @buyers [
    {"Softbridge Polska Sp. z o.o.", "Softbridge", "ul. Podgórska 34, 31-035 Kraków", "5260012385"},
    {"Kancelaria Radców Prawnych Nowak i Wspólnicy sp.k.", "Kancelaria Nowak i Wspólnicy",
     "ul. Grodzka 21/4, 31-001 Kraków", "6340021010"},
    {"Hotel Wawel Palace Sp. z o.o.", "Hotel Wawel Palace", "ul. Poselska 9, 31-002 Kraków", "9450033777"},
    {"Agencja Reklamowa Pixel Sp. z o.o.", "Pixel Agency", "ul. Lubicz 25, 31-503 Kraków", "6750044128"}
  ]

  @staff [
    {"Julia Wrona", 4_350},
    {"Michał Sowa", 4_180},
    {"Aleksandra Lis", 3_900}
  ]

  @doc "Seeds the café organization with ten months of data; no-op when it exists."
  def seed! do
    if cafe_exists?() do
      IO.puts("[seeds] Kawiarnia Ziarno already seeded — skipping")
    else
      kira =
        Ash.read_one!(Ash.Query.filter(CoreUser, email == ^"kira@bytecraft.collective"),
          authorize?: false
        )

      org = seed_organization(kira)
      Helpers.seed_member!(kira.id, org.id, :admin, %{name: "Kira Voss"})
      bank = seed_bank_account(org)
      ctx = %{org_id: org.id, bank_id: bank.id}

      seed_card_payouts(ctx)
      seed_delivery_payouts(ctx)
      seed_catering_invoices(ctx)
      seed_cost_invoices(ctx)
      seed_standalone_expenses(ctx)

      IO.puts("[seeds] Kawiarnia Ziarno seeded (org #{org.id}, NIP #{@nip})")
    end

    :ok
  end

  defp cafe_exists? do
    CoreOrganization
    |> Ash.Query.filter(nip == ^@nip)
    |> Ash.exists?(authorize?: false)
  end

  defp seed_organization(kira) do
    Ash.Seed.upsert!(
      CoreOrganization,
      %{
        name: @org_name,
        nip: @nip,
        address: @address,
        owner_id: kira.id,
        inbound_email_nickname: "ziarno",
        is_vat_payer: true
      },
      identity: :unique_nickname
    )
  end

  defp seed_bank_account(org) do
    requisition = Helpers.seed_requisition!("3c1f5a52-6b0e-4d7a-9a47-2f0c8e5b7d11", org.id)

    Helpers.seed_bank_account!(
      %{
        institution_id: "MBANK_BREXPLPW",
        institution_name: "mBank",
        owner_name: @org_name,
        iban: @iban,
        gocardless_id: "3c1f5a52-6b0e-4d7a-9a47-2f0c8e5b7d12",
        currency: "PLN",
        is_default: true,
        requisition_id: requisition.id
      },
      org.id
    )
  end

  # ===========================================================================
  # Income
  # ===========================================================================

  # Weekly acquirer payout on Tuesdays for the previous Monday–Sunday week.
  defp seed_card_payouts(ctx) do
    for date <- Date.range(first_day(), Helpers.today()), Date.day_of_week(date) == 2 do
      week_start = Date.add(date, -8)
      week_end = Date.add(date, -2)
      amount = 13_500 * season(date) * jitter({:card, date}, 0.12)

      incoming!(ctx, "card_#{date}", date, amount, "Fiserv Polska S.A.",
        remittance: "Rozliczenie transakcji kartowych #{week_start}..#{range_end(week_start, week_end)}"
      )
    end
  end

  defp seed_delivery_payouts(ctx) do
    for_each_month(fn first, f, _offset ->
      previous = Date.shift(first, month: -1)
      period = "#{Date.beginning_of_month(previous)}..#{Date.end_of_month(previous)}"

      with_date(first, 9, fn date ->
        incoming!(
          ctx,
          "pyszne_#{date}",
          date,
          6_400 * f * jitter({:pyszne, date}, 0.1),
          "Takeaway.com Polska Sp. z o.o.",
          remittance: "Wypłata Pyszne.pl za zamówienia #{period}"
        )
      end)

      with_date(first, 12, fn date ->
        incoming!(
          ctx,
          "glovo_#{date}",
          date,
          4_300 * f * jitter({:glovo, date}, 0.1),
          "Glovoapp Poland Sp. z o.o.",
          remittance: "Rozliczenie Glovo za okres #{period}"
        )
      end)
    end)
  end

  defp seed_catering_invoices(ctx) do
    for_each_month(fn first, f, offset ->
      with_date(first, 18, fn payment_date ->
        catering_invoice!(ctx, first, 6, payment_date, 0, offset, f)
      end)

      if rem(offset, 2) == 1 do
        with_date(first, 26, fn payment_date ->
          catering_invoice!(ctx, first, 14, payment_date, 1, offset, f)
        end)
      end
    end)
  end

  defp catering_invoice!(ctx, first, issue_day, payment_date, slot, offset, f) do
    issue_date = date_in(first, issue_day)

    {buyer_name, buyer_display, buyer_address, buyer_nip} =
      Enum.at(@buyers, rem(offset + slot, length(@buyers)))

    people = round(18 + :erlang.phash2({:people, first, slot}, 22) * f)

    items = [
      %{
        "name" => "Catering – spotkanie zespołu (kawa, ciasta, kanapki)",
        "quantity" => people,
        "unit" => "os.",
        "unit_price" => 42.0,
        "vat_rate" => "8"
      },
      %{
        "name" => "Obsługa baristy na miejscu",
        "quantity" => 1,
        "unit" => "usł.",
        "unit_price" => 350.0,
        "vat_rate" => "23"
      }
    ]

    number = "KZ/#{String.pad_leading("#{slot + 1}", 2, "0")}/#{Helpers.month_prefix(offset)}"

    invoice =
      Helpers.get_or_create_sales_invoice(number, ctx.org_id, %{
        "invoice_type" => "poland",
        "issue_date" => issue_date,
        "sale_date" => issue_date,
        "due_date" => Date.add(issue_date, 14),
        "currency" => "PLN",
        "seller_display_name" => @org_name,
        "seller_address" => @address,
        "seller_nip" => @nip,
        "seller_account_number" => @iban,
        "buyer_display_name" => buyer_display,
        "buyer_full_name" => buyer_name,
        "buyer_address" => buyer_address,
        "buyer_country" => "PL",
        "buyer_id" => buyer_nip,
        "buyer_type" => "company",
        "payment_method" => "transfer",
        "is_reverse_charge" => false,
        "is_cash_account" => false,
        "sales_invoice_items" => items
      })

    gross =
      Enum.reduce(items, Decimal.new(0), fn item, acc ->
        Decimal.add(acc, gross_line(item["quantity"], item["unit_price"], item["vat_rate"]))
      end)

    transaction =
      transaction!(ctx, "catering_#{number}", payment_date, gross,
        counterparty: buyer_name,
        remittance: "Faktura #{number} – catering",
        skip_invoicing: false
      )

    Helpers.connect_sales_invoice_transaction!(invoice.id, transaction.id, ctx.org_id)
  end

  # ===========================================================================
  # Costs
  # ===========================================================================

  defp seed_cost_invoices(ctx) do
    for_each_month(fn first, f, offset ->
      for %{vendor: vendor, key: key, day: day} = spec <- cost_specs(offset, f) do
        with_date(first, day + 2, fn payment_date ->
          cost_invoice!(ctx, vendor, key, date_in(first, day), payment_date, spec)
        end)
      end
    end)
  end

  defp cost_invoice!(ctx, vendor, key, issue_date, payment_date, spec) do
    {seller, display, address} = Map.fetch!(@vendors, vendor)

    net =
      Enum.reduce(
        spec.items,
        Decimal.new(0),
        &Decimal.add(&2, net_line(&1["quantity"], &1["price"]))
      )

    vat =
      if vendor == :meta,
        do: Decimal.new(0),
        else: Decimal.round(Decimal.mult(net, Decimal.div(spec.vat, 100)), 2)

    gross = Decimal.add(net, vat)

    identifier =
      "#{spec.prefix}/#{key}/#{issue_date.year}/#{String.pad_leading("#{issue_date.month}", 2, "0")}"

    invoice =
      Helpers.get_or_create_cost_invoice(identifier, ctx.org_id, %{
        seller: seller,
        seller_display_name: display,
        seller_address: address,
        sale_date: issue_date,
        issue_date: issue_date,
        due_date: Date.add(issue_date, 14),
        amount: Helpers.money!("PLN", Decimal.negate(gross)),
        deductible_vat_amount: Helpers.money!("PLN", vat),
        description: spec.description,
        items_list: spec.items,
        skip_invoicing: false
      })

    transaction =
      transaction!(ctx, "cost_#{identifier}", payment_date, Decimal.negate(gross),
        counterparty: seller,
        remittance: "Faktura #{identifier} – #{spec.description}",
        skip_invoicing: false
      )

    Helpers.connect_cost_invoice_transaction!(invoice.id, transaction.id, ctx.org_id)
  end

  # Invoices of one month. `f` is the seasonality factor: variable costs follow
  # the traffic, fixed ones (rent, subscriptions) do not.
  defp cost_specs(offset, f) do
    makro_days = if rem(offset, 2) == 0, do: [4, 14, 24], else: [5, 19]
    month = Date.beginning_of_month(Helpers.months_ago(offset))

    makro =
      makro_days
      |> Enum.with_index(1)
      |> Enum.map(fn {day, index} ->
        spec(
          :makro,
          "M#{index}",
          day,
          "Makro: nabiał, cukier, kubki, syropy",
          23,
          makro_items(index, f, month)
        )
      end)

    coffee =
      for {day, index} <- Enum.with_index([7, 21], 1) do
        items = [
          item(
            "Kawa ziarnista espresso 1 kg",
            28 * f * jitter({:coffee, month, index}, 0.08),
            89.0
          ),
          item("Kawa ziarnista single origin 1 kg", 6, 112.0)
        ]

        spec(:coffeelab, "K#{index}", day, "Kawa ziarnista do ekspresu", 23, items)
      end

    bakery =
      for {day, index} <- Enum.with_index([2, 9, 16, 23], 1) do
        scale = f * jitter({:bakery, month, index}, 0.08)

        items = [
          item("Croissant maślany", 150 * scale, 3.2),
          item("Chleb na zakwasie 600 g", 45 * scale, 9.5),
          item("Drożdżówka z serem", 80 * scale, 2.8)
        ]

        spec(:bakery, "P#{index}", day, "Pieczywo i wypieki", 5, items)
      end

    fixed = [
      spec(:rent, "C", 5, "Czynsz za lokal i opłaty eksploatacyjne", 23, [
        item("Czynsz za lokal – ul. Józefa 12", 1, 9_800.0),
        item("Opłaty eksploatacyjne", 1, 1_900.0)
      ]),
      spec(:pge, "E", 8, "Energia elektryczna", 23, [
        item("Energia elektryczna – sprzedaż (kWh)", 2_300 * jitter({:pge, month}, 0.06), 0.89),
        item("Opłata dystrybucyjna", 1, 420.0)
      ]),
      spec(:gas, "G", 8, "Paliwo gazowe", 23, [
        item("Paliwo gazowe (kWh)", 1_400 * (2 - f) * jitter({:gas, month}, 0.06), 0.31),
        item("Opłata abonamentowa", 1, 24.0)
      ]),
      spec(:orange, "I", 11, "Internet światłowodowy", 23, [
        item("Internet światłowodowy Biznes 600 Mb/s", 1, 129.0)
      ]),
      spec(:meta, "R", 15, "Reklama Instagram", 0, [
        item(
          "Reklama Instagram – kampania lokalna",
          1,
          Float.round(1_450 * f * jitter({:meta, month}, 0.1), 2)
        )
      ]),
      spec(:bilans, "B", 3, "Usługi księgowe", 23, [
        item("Usługi księgowe – miesięczna obsługa", 1, 950.0),
        item("Obsługa kadrowo-płacowa (osoby)", 3, 60.0)
      ]),
      spec(:glovo, "GL", 6, "Prowizja od zamówień Glovo", 23, [
        item(
          "Prowizja od zamówień Glovo",
          1,
          Float.round(1_250 * f * jitter({:glovo_fee, month}, 0.1), 2)
        )
      ]),
      spec(:takeaway, "PY", 6, "Prowizja od zamówień Pyszne.pl", 23, [
        item(
          "Prowizja od zamówień Pyszne.pl",
          1,
          Float.round(1_650 * f * jitter({:pyszne_fee, month}, 0.1), 2)
        )
      ]),
      spec(:fiserv, "T", 12, "Opłata za terminal płatniczy", 23, [
        item("Opłata za terminal płatniczy", 1, 149.0),
        item("Prowizja od transakcji kartowych", 1, Float.round(360 * f, 2))
      ])
    ]

    fixed = if rem(offset, 3) == 0, do: [allegro_spec(offset) | fixed], else: fixed

    makro ++ coffee ++ bakery ++ fixed
  end

  defp makro_items(1, f, month) do
    [
      item("Mleko UHT 3,2% 1 l", 160 * f * jitter({:milk, month}, 0.08), 3.45),
      item("Mleko owsiane barista 1 l", 60 * f, 7.9),
      item("Cukier biały 1 kg", 40, 3.89),
      item("Syrop waniliowy 0,7 l", 8, 21.9)
    ]
  end

  defp makro_items(2, f, month) do
    [
      item("Kubki papierowe 300 ml (op. 50 szt.)", 120 * f * jitter({:cups, month}, 0.08), 14.5),
      item("Pokrywki do kubków 300 ml (op. 100 szt.)", 60 * f, 11.2),
      item("Syrop karmelowy 0,7 l", 8, 21.9),
      item("Śmietanka 30% 1 l", 30 * f, 11.2)
    ]
  end

  defp makro_items(_index, f, month) do
    [
      item("Mleko UHT 3,2% 1 l", 120 * f * jitter({:milk3, month}, 0.08), 3.45),
      item("Czekolada do picia 1 kg", 10, 34.0),
      item("Cukier biały 1 kg", 30, 3.89),
      item("Ręcznik papierowy (op. 6 rolek)", 12, 18.5)
    ]
  end

  defp allegro_spec(offset) do
    {description, items} =
      case offset do
        9 ->
          {"Młynek do kawy", [item("Młynek do kawy Eureka Mignon Specialita", 1, 2_650.0)]}

        6 ->
          {"Ściereczki i dzbanki",
           [
             item("Ściereczki z mikrofibry (zestaw 20 szt.)", 3, 39.0),
             item("Dzbanek do spieniania mleka 600 ml", 4, 49.0)
           ]}

        3 ->
          {"Akcesoria baristy", [item("Tamper do kawy 58 mm", 2, 89.0), item("Waga barista z timerem", 1, 119.0)]}

        _ ->
          {"Tablica i wyposażenie sali",
           [
             item("Tablica kredowa stojąca A-frame", 1, 189.0),
             item("Kredy płynne (zestaw 8 szt.)", 2, 35.0)
           ]}
      end

    spec(:allegro, "AL", 17, description, 23, items)
  end

  defp spec(vendor, key, day, description, vat, items) do
    %{
      vendor: vendor,
      key: key,
      prefix: vendor |> Atom.to_string() |> String.upcase() |> binary_part(0, 3),
      day: day,
      description: description,
      vat: Decimal.new(vat),
      items: items
    }
  end

  defp item(name, quantity, price), do: %{"name" => name, "quantity" => max(1, round(quantity)), "price" => price}

  # ===========================================================================
  # Standalone transactions (no invoice, included in the analysis)
  # ===========================================================================

  defp seed_standalone_expenses(ctx) do
    for_each_month(fn first, f, offset ->
      with_date(first, 10, fn date ->
        outgoing!(
          ctx,
          "zus_#{date}",
          date,
          4_150 + :erlang.phash2({:zus, date}, 120),
          "Zakład Ubezpieczeń Społecznych",
          remittance: "Składki ZUS za #{previous_period(date)}, NIP #{@nip}"
        )

        for {{name, net}, index} <- Enum.with_index(@staff, 1) do
          outgoing!(ctx, "salary_#{index}_#{date}", date, net, name,
            remittance: "Wynagrodzenie za #{previous_period(date)}"
          )
        end
      end)

      with_date(first, 20, fn date ->
        outgoing!(
          ctx,
          "tax_#{date}",
          date,
          2_800 * f + :erlang.phash2({:tax, date}, 400),
          "Urząd Skarbowy Kraków-Śródmieście",
          remittance: "VAT-7 i PIT-4 za #{previous_period(date)}, NIP #{@nip}"
        )
      end)

      with_date(first, 13, fn date ->
        {payee, remittance} =
          if rem(offset, 2) == 1,
            do: {"ORLEN STACJA NR 123 KRAKOW", "Płatność kartą ORLEN STACJA NR 123 KRAKOW – paliwo, dostawy"},
            else: {"LIDL KRAKOW UL. KRAKOWSKA 17", "Płatność kartą LIDL KRAKOW UL. KRAKOWSKA 17 – zakupy bieżące"}

        outgoing!(ctx, "card_#{date}", date, 180 + :erlang.phash2({:card, date}, 240), payee, remittance: remittance)
      end)
    end)
  end

  # ===========================================================================
  # Helpers
  # ===========================================================================

  defp incoming!(ctx, key, date, amount, debtor, opts) do
    transaction!(
      ctx,
      key,
      date,
      amount,
      Keyword.merge([counterparty: debtor, skip_invoicing: true], opts)
    )
  end

  defp outgoing!(ctx, key, date, amount, creditor, opts) do
    transaction!(
      ctx,
      key,
      date,
      Decimal.negate(to_decimal(amount)),
      Keyword.merge([counterparty: creditor, skip_invoicing: true], opts)
    )
  end

  # Positive amount: incoming from `counterparty`; negative: outgoing to it.
  defp transaction!(ctx, key, date, amount, opts) do
    amount = to_decimal(amount)
    counterparty = Keyword.fetch!(opts, :counterparty)
    incoming? = Decimal.positive?(amount)
    counterparty_account = fake_iban(counterparty)

    Helpers.seed_transaction!(
      %{
        internal_transaction_id: "cafe_#{key}",
        creditor_name: if(incoming?, do: @org_name, else: counterparty),
        creditor_account: if(incoming?, do: @iban, else: counterparty_account),
        debtor_name: if(incoming?, do: counterparty, else: @org_name),
        debtor_account: if(incoming?, do: counterparty_account, else: @iban),
        amount: Helpers.money!("PLN", amount),
        booking_date: date,
        bank_account_id: ctx.bank_id,
        skip_invoicing: Keyword.fetch!(opts, :skip_invoicing),
        remittance_information_unstructured: Keyword.fetch!(opts, :remittance)
      },
      ctx.org_id
    )
  end

  defp to_decimal(%Decimal{} = value), do: Decimal.round(value, 2)
  defp to_decimal(value) when is_integer(value), do: Decimal.new(value)

  defp to_decimal(value) when is_float(value), do: value |> Decimal.from_float() |> Decimal.round(2)

  defp net_line(quantity, price),
    do: quantity |> Decimal.new() |> Decimal.mult(to_decimal_price(price)) |> Decimal.round(2)

  defp gross_line(quantity, price, vat_rate) do
    net = net_line(quantity, price)

    Decimal.add(
      net,
      net |> Decimal.mult(Decimal.div(Decimal.new(vat_rate), 100)) |> Decimal.round(2)
    )
  end

  defp to_decimal_price(price) when is_float(price), do: Decimal.from_float(price)
  defp to_decimal_price(price) when is_integer(price), do: Decimal.new(price)

  defp fake_iban(name) do
    digits =
      for part <- 1..3,
          into: "",
          do: String.pad_leading("#{:erlang.phash2({name, part}, 1_000_000_000)}", 9, "0")

    "PL" <> binary_part(digits, 0, 26)
  end

  # Deterministic multiplier in 1 ± spread.
  defp jitter(key, spread), do: 1 + (:erlang.phash2(key, 2001) - 1000) / 1000 * spread

  defp season(date), do: Map.fetch!(@seasonality, date.month)

  defp first_day, do: Date.beginning_of_month(Helpers.months_ago(@months_back))

  defp range_end(week_start, week_end) do
    if week_start.month == week_end.month, do: "#{week_end.day}", else: "#{week_end}"
  end

  defp previous_period(date) do
    previous = Date.shift(date, month: -1)
    "#{String.pad_leading("#{previous.month}", 2, "0")}/#{previous.year}"
  end

  defp date_in(first, day), do: Date.new!(first.year, first.month, min(day, Date.days_in_month(first)))

  # Runs `fun` only when the date is not in the future.
  defp with_date(first, day, fun) do
    date = date_in(first, day)
    if Date.compare(date, Helpers.today()) != :gt, do: fun.(date)
  end

  # Calls `fun` with the first day of every month, its seasonality factor and its offset.
  defp for_each_month(fun) do
    Enum.each(@months_back..0//-1, fn offset ->
      first = Date.beginning_of_month(Helpers.months_ago(offset))
      f = Map.fetch!(@seasonality, first.month)

      fun.(first, f, offset)
    end)
  end
end
