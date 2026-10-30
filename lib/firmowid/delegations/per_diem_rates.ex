defmodule Firmowid.Delegations.PerDiemRates do
  @moduledoc """
  Statutory per-diem rates and foreign accommodation limits for business trips.

  The rates come from the regulation on business-trip allowances (Dz.U. 2013 poz. 167,
  consolidated text Dz.U. 2023 poz. 2190): § 7 for domestic trips and its annex for
  foreign ones. `source/0` records the legal state the table reflects.
  """

  @source %{
    act: "DU/2013/167",
    amending_acts: ["DU/2022/1481", "DU/2022/2302"],
    consolidated_text: "DU/2023/2190"
  }

  @domestic_per_diem 45

  # {country code, name in the annex, currency, per diem, accommodation limit}
  @foreign_rates [
    {"AF", "Afganistan", :EUR, 47, 140},
    {"AL", "Albania", :EUR, 41, 120},
    {"DZ", "Algieria", :EUR, 50, 200},
    {"AD", "Andora", :EUR, 50, 200},
    {"AO", "Angola", :USD, 61, 180},
    {"SA", "Arabia Saudyjska", :EUR, 50, 200},
    {"AR", "Argentyna", :USD, 50, 150},
    {"AM", "Armenia", :EUR, 42, 145},
    {"AU", "Australia", :AUD, 95, 270},
    {"AT", "Austria", :EUR, 57, 150},
    {"AZ", "Azerbejdżan", :EUR, 43, 150},
    {"BD", "Bangladesz", :USD, 50, 120},
    {"BE", "Belgia", :EUR, 55, 200},
    {"BY", "Białoruś", :EUR, 42, 130},
    {"BA", "Bośnia i Hercegowina", :EUR, 41, 100},
    {"BR", "Brazylia", :EUR, 43, 120},
    {"BG", "Bułgaria", :EUR, 40, 120},
    {"CL", "Chile", :USD, 60, 120},
    {"CN", "Chiny", :EUR, 55, 170},
    {"HR", "Chorwacja", :EUR, 42, 125},
    {"CY", "Cypr", :EUR, 43, 160},
    {"ME", "Czarnogóra", :EUR, 40, 110},
    {"CZ", "Czechy", :EUR, 41, 120},
    {"DK", "Dania", :DKK, 446, 1430},
    {"CD", "Demokratyczna Republika Konga", :USD, 66, 220},
    {"EG", "Egipt", :USD, 55, 150},
    {"EC", "Ekwador", :USD, 44, 110},
    {"EE", "Estonia", :EUR, 45, 110},
    {"ET", "Etiopia", :USD, 55, 300},
    {"FI", "Finlandia", :EUR, 53, 180},
    {"FR", "Francja", :EUR, 55, 200},
    {"GR", "Grecja", :EUR, 50, 160},
    {"GE", "Gruzja", :EUR, 48, 160},
    {"ES", "Hiszpania", :EUR, 50, 200},
    {"NL", "Holandia", :EUR, 50, 150},
    {"IN", "Indie", :EUR, 42, 210},
    {"ID", "Indonezja", :EUR, 41, 110},
    {"IQ", "Irak", :USD, 60, 120},
    {"IR", "Iran", :EUR, 41, 95},
    {"IE", "Irlandia", :EUR, 52, 160},
    {"IS", "Islandia", :EUR, 56, 160},
    {"IL", "Izrael", :EUR, 70, 200},
    {"JP", "Japonia", :JPY, 7532, 22_000},
    {"YE", "Jemen", :USD, 48, 160},
    {"JO", "Jordania", :EUR, 50, 130},
    {"KH", "Kambodża", :USD, 45, 100},
    {"CA", "Kanada", :CAD, 71, 190},
    {"QA", "Katar", :EUR, 41, 200},
    {"KZ", "Kazachstan", :EUR, 45, 155},
    {"KE", "Kenia", :EUR, 41, 150},
    {"KG", "Kirgistan", :USD, 41, 150},
    {"CO", "Kolumbia", :USD, 49, 120},
    {"CG", "Kongo", :USD, 66, 220},
    {"KR", "Korea Południowa", :EUR, 46, 170},
    {"KP", "Korea Północna", :EUR, 48, 170},
    {"CR", "Kostaryka", :USD, 50, 140},
    {"CU", "Kuba", :EUR, 50, 140},
    {"KW", "Kuwejt", :EUR, 39, 200},
    {"LA", "Laos", :USD, 54, 100},
    {"LB", "Liban", :USD, 57, 150},
    {"LY", "Libia", :EUR, 52, 100},
    {"LI", "Liechtenstein", :CHF, 88, 220},
    {"LT", "Litwa", :EUR, 45, 150},
    {"LU", "Luksemburg", :EUR, 55, 200},
    {"LV", "Łotwa", :EUR, 57, 132},
    {"MK", "Macedonia Północna", :EUR, 43, 138},
    {"MY", "Malezja", :EUR, 41, 140},
    {"MT", "Malta", :EUR, 43, 180},
    {"MA", "Maroko", :EUR, 41, 130},
    {"MX", "Meksyk", :USD, 58, 154},
    {"MD", "Mołdawia", :EUR, 45, 94},
    {"MC", "Monako", :EUR, 55, 200},
    {"MN", "Mongolia", :EUR, 45, 154},
    {"DE", "Niemcy", :EUR, 49, 170},
    {"NG", "Nigeria", :EUR, 46, 240},
    {"NO", "Norwegia", :NOK, 496, 1650},
    {"NZ", "Nowa Zelandia", :USD, 58, 180},
    {"OM", "Oman", :EUR, 40, 240},
    {"PK", "Pakistan", :EUR, 38, 200},
    {"PS", "Palestyna", :EUR, 70, 200},
    {"PA", "Panama", :USD, 52, 140},
    {"PE", "Peru", :USD, 50, 150},
    {"ZA", "Południowa Afryka", :USD, 52, 275},
    {"PT", "Portugalia", :EUR, 49, 150},
    {"RU", "Rosja", :EUR, 48, 200},
    {"RO", "Rumunia", :EUR, 42, 110},
    {"SM", "San Marino", :EUR, 53, 192},
    {"SN", "Senegal", :EUR, 44, 120},
    {"RS", "Serbia", :EUR, 40, 110},
    {"SG", "Singapur", :USD, 56, 230},
    {"SK", "Słowacja", :EUR, 47, 132},
    {"SI", "Słowenia", :EUR, 45, 143},
    {"US", "Stany Zjednoczone Ameryki", :USD, 59, 200},
    {"SY", "Syria", :USD, 50, 150},
    {"CH", "Szwajcaria", :CHF, 88, 220},
    {"SE", "Szwecja", :SEK, 510, 2000},
    {"TJ", "Tadżykistan", :EUR, 41, 140},
    {"TH", "Tajlandia", :USD, 42, 110},
    {"TZ", "Tanzania", :USD, 53, 150},
    {"TN", "Tunezja", :EUR, 37, 100},
    {"TR", "Turcja", :USD, 53, 185},
    {"TM", "Turkmenistan", :EUR, 47, 90},
    {"UA", "Ukraina", :EUR, 41, 180},
    {"UY", "Urugwaj", :USD, 50, 80},
    {"UZ", "Uzbekistan", :EUR, 41, 140},
    {"VA", "Watykan", :EUR, 53, 192},
    {"VE", "Wenezuela", :USD, 60, 220},
    {"HU", "Węgry", :EUR, 44, 143},
    {"GB", "Wielka Brytania", :GBP, 45, 220},
    {"VN", "Wietnam", :USD, 53, 160},
    {"IT", "Włochy", :EUR, 53, 192},
    {"CI", "Wybrzeże Kości Słoniowej", :EUR, 33, 100},
    {"ZW", "Zimbabwe", :EUR, 39, 90},
    {"AE", "Zjednoczone Emiraty Arabskie", :EUR, 43, 220}
  ]

  # Territories named below the annex table.
  @territory_rates [
    {"GI", "Gibraltar", :GBP, 45, 220},
    {"HK", "Hongkong", :USD, 55, 250},
    {"TW", "Tajwan", :EUR, 40, 142}
  ]

  @other_countries_rate {:EUR, 41, 140}

  # The country select uses KSeF codes: Greece is EL, Northern Ireland XI, Ceuta XC and Melilla XL.
  @country_aliases %{"EL" => "GR", "XI" => "GB", "XC" => "ES", "XL" => "ES"}

  @accommodation_city_limits %{"US" => %{"Nowy Jork" => 350, "Waszyngton" => 300}}

  @rates Map.new(@foreign_rates ++ @territory_rates, fn {code, _name, currency, per_diem, limit} ->
           {code, {currency, per_diem, limit}}
         end)

  @type foreign_rate :: %{
          per_diem: Money.t(),
          accommodation_limit: Money.t(),
          accommodation_city_limits: %{String.t() => Money.t()}
        }

  @doc "Returns the act, amending acts and consolidated text the table reflects."
  @spec source() :: %{act: String.t(), amending_acts: [String.t()], consolidated_text: String.t()}
  def source, do: @source

  @doc "Returns the daily per diem for a domestic trip."
  @spec domestic_per_diem() :: Money.t()
  def domestic_per_diem, do: Money.new(:PLN, @domestic_per_diem)

  @doc "Returns the foreign per diem and accommodation limits for a country code."
  @spec foreign(String.t()) :: foreign_rate()
  def foreign(country_code) when is_binary(country_code) do
    country_code = Map.get(@country_aliases, country_code, country_code)
    {currency, per_diem, limit} = Map.get(@rates, country_code, @other_countries_rate)

    %{
      per_diem: Money.new(currency, per_diem),
      accommodation_limit: Money.new(currency, limit),
      accommodation_city_limits:
        @accommodation_city_limits
        |> Map.get(country_code, %{})
        |> Map.new(fn {city, city_limit} -> {city, Money.new(currency, city_limit)} end)
    }
  end
end
