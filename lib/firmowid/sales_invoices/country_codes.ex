defmodule Firmowid.SalesInvoices.CountryCodes do
  @moduledoc """
  Provides country code validation and EU country identification
  based on KSeF XSD schemas (KodyKrajow_v10-0E.xsd and schemat.xsd).

  Uses ex_cldr_territories for localized country names in Polish.
  """

  alias Firmowid.Cldr.Territory

  # All valid ISO country codes from KodyKrajow_v10-0E.xsd
  # Note: Greece uses EL (not GR) in official KSeF, but we accept both and normalize
  @valid_country_codes ~w(
    AF AX AL DZ AD AO AI AQ AG AN SA AR AM AW AU AT AZ BS BH BD BB BE BZ BJ BM
    BT BY BO BQ BA BW BR BN IO BG BF BI XC CL CN HR CW CY TD ME DK DM DO DJ EG
    EC ER EE ET FK FJ PH FI FR TF GA GM GH GI GR GD GL GE GU GG GY GF GP GT GN
    GQ GW HT ES HN HK IN ID IQ IR IE IS IL JM JP YE JE JO KY KH CM CA QA KZ KE
    KG KI CO KM CG CD KP XK CR CU KW LA LS LB LR LY LI LT LV LU MK MG YT MO MW
    MV MY ML MT MP MA MQ MR MU MX XL FM UM MD MC MN MS MZ MM NA NR NP NL DE NE
    NG NI NU NF NO NC NZ PS OM PK PW PA PG PY PE PN PF PL GS PT PR CF CZ KR ZA
    RE RU RO RW EH BL KN LC MF VC SV WS AS SM SN RS SC SL SG SK SI SO LK PM US
    SZ SD SS SR SJ SH SY CH SE TJ TH TW TZ TG TK TO TT TN TR TM TV UG UA UY UZ
    VU WF VA HU VE GB VN IT TL CI BV CX IM SX CK VI VG HM CC MH FO SB ST TC ZM
    CV ZW AE XI EL
  )

  # EU country codes from schemat.xsd TKodyKrajowUE
  # Note: XI is Northern Ireland (special status post-Brexit)
  @eu_country_codes ~w(
    AT BE BG CY CZ DK EE FI FR DE EL HR HU IE IT LV LT LU MT NL PL PT RO SK SI
    ES SE XI
  )

  # Mapping from KSeF special codes to CLDR territory codes or Polish names
  # EL -> GR (Greece uses EL in KSeF but GR in ISO/CLDR)
  # XI -> Northern Ireland (special post-Brexit status)
  # XC, XL -> KSeF-specific codes without CLDR equivalents
  @special_code_names %{
    "EL" => "Grecja",
    "XI" => "Irlandia Północna",
    "XC" => "Ceuta",
    "XL" => "Melilla"
  }

  @spec all_countries() :: [String.t()]
  def all_countries, do: @valid_country_codes

  @spec eu_countries() :: [String.t()]
  def eu_countries, do: @eu_country_codes

  @spec valid_country?(String.t() | nil) :: boolean()
  def valid_country?(code) when is_binary(code) do
    code in @valid_country_codes
  end

  def valid_country?(_), do: false

  @spec eu_country?(String.t() | nil) :: boolean()
  def eu_country?(code) when is_binary(code) do
    normalize(code) in @eu_country_codes
  end

  def eu_country?(_), do: false

  @spec normalize(String.t() | nil) :: String.t() | nil
  def normalize("GR"), do: "EL"
  def normalize(code), do: code

  @spec region(String.t() | nil) :: :eu | :non_eu | :invalid
  def region(code) when is_binary(code) do
    normalized = normalize(code)

    cond do
      normalized in @eu_country_codes -> :eu
      valid_country?(normalized) -> :non_eu
      true -> :invalid
    end
  end

  def region(_), do: :invalid

  @doc """
  Returns a list of country options for select inputs.

  Each option is a tuple of `{display_name, code}` where:
  - `display_name` is the Polish name of the country
  - `code` is the KSeF-compatible ISO code

  EU countries are listed first (sorted alphabetically by name),
  followed by non-EU countries (also sorted alphabetically by name).
  """
  @spec country_options() :: [{String.t(), String.t()}]
  def country_options do
    eu_options =
      @eu_country_codes
      |> Enum.map(&{country_name(&1), &1})
      |> Enum.sort_by(fn {name, _code} -> name end)

    non_eu_options =
      @valid_country_codes
      |> Enum.reject(&(&1 in @eu_country_codes))
      |> Enum.map(&{country_name(&1), &1})
      |> Enum.sort_by(fn {name, _code} -> name end)

    eu_options ++ non_eu_options
  end

  @doc """
  Returns the Polish name for a country code.

  Uses CLDR territories for standard ISO codes, with fallbacks for
  KSeF-specific codes (EL for Greece, XI for Northern Ireland, etc.).
  """
  @spec country_name(String.t()) :: String.t()
  def country_name(code) when is_binary(code) do
    case Map.fetch(@special_code_names, code) do
      {:ok, name} ->
        name

      :error ->
        # Safe to use String.to_atom since we only call this for validated country codes
        territory_code = String.to_atom(code)

        case Territory.from_territory_code(territory_code) do
          {:ok, name} -> name
          {:error, _} -> code
        end
    end
  end
end
