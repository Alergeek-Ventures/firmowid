defmodule Firmowid.SalesInvoices.CountryCodes do
  @moduledoc """
  Provides country code validation and EU country identification
  based on KSeF XSD schemas (KodyKrajow_v10-0E.xsd and schemat.xsd).
  """

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

  @spec country_options() :: [{String.t(), String.t()}]
  def country_options do
    eu_sorted = Enum.sort(@eu_country_codes)

    non_eu_sorted =
      @valid_country_codes
      |> Enum.reject(&(&1 in @eu_country_codes))
      |> Enum.sort()

    eu_options = Enum.map(eu_sorted, &{&1, &1})
    non_eu_options = Enum.map(non_eu_sorted, &{&1, &1})

    eu_options ++ non_eu_options
  end
end
