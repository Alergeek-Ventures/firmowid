defmodule Firmowid.Invoicing.EuVatNumber do
  @moduledoc """
  National structure of a buyer's EU VAT number (VAT-UE), country by country.

  KSeF's `TNrVatUE` pattern, enforced by `ValidateTaxId`, accepts any 1–12 letters
  and digits, so a Swedish organisation number without its `01` suffix passes it.
  This module checks the structure each member state uses and, where the check
  digit is implemented, the checksum. A well-formed number is not proof of
  registration; only VIES confirms that (`EuVatRegistration`).

  Numbers are kept without the country prefix: KSeF writes the country to `KodUE`
  and the number to `NrVatUE`.
  """

  alias Firmowid.Invoicing.CountryCodes

  # Structures follow python-stdnum (https://github.com/arthurdejong/python-stdnum,
  # stdnum/<country>/vat.py). Patterns stay permissive where the national rule depends
  # on a checksum this module does not implement: a rejected number cannot be issued,
  # so a stricter guess would block valid invoices.
  @formats %{
    "AT" => {~r/^U\d{8}$/, "U99999999"},
    "BE" => {~r/^[01]\d{9}$/, "0999999999"},
    "BG" => {~r/^\d{9,10}$/, "999999999"},
    "CY" => {~r/^\d{8}[A-Z]$/, "99999999X"},
    "CZ" => {~r/^\d{8,10}$/, "99999999"},
    "DE" => {~r/^\d{9}$/, "999999999"},
    "DK" => {~r/^\d{8}$/, "99999999"},
    "EE" => {~r/^\d{9}$/, "999999999"},
    "EL" => {~r/^\d{9}$/, "999999999"},
    "ES" => {~r/^[0-9A-Z]\d{7}[0-9A-Z]$/, "X9999999X"},
    "FI" => {~r/^\d{8}$/, "99999999"},
    "FR" => {~r/^[0-9A-Z]{2}\d{9}$/, "XX999999999"},
    "HR" => {~r/^\d{11}$/, "99999999999"},
    "HU" => {~r/^\d{8}$/, "99999999"},
    "IE" => {~r/^(\d{7}[A-Z]{1,2}|\d[A-Z+*]\d{5}[A-Z])$/, "9999999X"},
    "IT" => {~r/^\d{11}$/, "99999999999"},
    "LT" => {~r/^(\d{9}|\d{12})$/, "999999999"},
    "LU" => {~r/^\d{8}$/, "99999999"},
    "LV" => {~r/^\d{11}$/, "99999999999"},
    "MT" => {~r/^\d{8}$/, "99999999"},
    "NL" => {~r/^\d{9}B\d{2}$/, "999999999B99"},
    "PT" => {~r/^\d{9}$/, "999999999"},
    "RO" => {~r/^\d{2,10}$/, "9999999999"},
    "SE" => {~r/^\d{10}01$/, "999999999901"},
    "SI" => {~r/^\d{8}$/, "99999999"},
    "SK" => {~r/^\d{10}$/, "9999999999"},
    "XI" => {~r/^(\d{9}|\d{12}|GD\d{3}|HA\d{3})$/, "999999999"}
  }

  @typedoc "A corrected number, or a different buyer country whose number the input already is."
  @type suggestion :: {:number, String.t()} | {:country, String.t(), String.t()}

  @type result ::
          {:ok, String.t()}
          | {:error, :format | :checksum, [suggestion()]}
          | :not_applicable

  @doc """
  Checks `number` against the VAT number structure of `country`.

  Returns the normalized number, or the failed rule with suggestions that would pass.
  Countries without VAT-UE rules here (Poland uses NIP, non-EU countries) return
  `:not_applicable`.
  """
  @spec check(String.t() | nil, String.t() | nil) :: result()
  def check(country, number) when is_binary(country) and is_binary(number) do
    country = CountryCodes.normalize(country)

    case Map.fetch(@formats, country) do
      {:ok, _format} -> check_number(country, number, normalize(number))
      :error -> :not_applicable
    end
  end

  def check(_country, _number), do: :not_applicable

  @doc "Returns the VIES-style pattern of a country's VAT number (9 is a digit, X a letter), or nil."
  @spec pattern(String.t() | nil) :: String.t() | nil
  def pattern(country) when is_binary(country) do
    case Map.fetch(@formats, CountryCodes.normalize(country)) do
      {:ok, {_regex, pattern}} -> pattern
      :error -> nil
    end
  end

  def pattern(_country), do: nil

  @doc "Uppercases the number and removes separators, keeping the `+` and `*` some Irish numbers use."
  @spec normalize(String.t()) :: String.t()
  def normalize(number), do: number |> String.upcase() |> String.replace(~r/[^0-9A-Z+*]/, "")

  # KSeF receives the number as written, and `NrVatUE` takes only capital letters
  # and digits, so a separator or a lowercase letter is a format error too.
  defp check_number(country, written, number) do
    case validate(country, number) do
      :ok when written == number -> {:ok, number}
      :ok -> {:error, :format, [{:number, number}]}
      {:error, rule} -> {:error, rule, suggestions(country, number)}
    end
  end

  defp validate(country, number) do
    {regex, _pattern} = Map.fetch!(@formats, country)

    cond do
      not Regex.match?(regex, number) -> {:error, :format}
      checksum_valid?(country, number) -> :ok
      true -> {:error, :checksum}
    end
  end

  # Swedish VAT number: organisation number with a Luhn check digit, then "01".
  defp checksum_valid?("SE", number), do: luhn_valid?(binary_part(number, 0, 10))
  defp checksum_valid?(_country, _number), do: true

  defp suggestions(country, number) do
    own =
      [number, strip_prefix(number, country)]
      |> Enum.flat_map(&repairs(country, &1))
      |> Enum.uniq()
      |> Enum.filter(&(&1 != number and validate(country, &1) == :ok))
      |> Enum.map(&{:number, &1})

    own ++ foreign_prefix(country, number)
  end

  # A Swedish organisation number alone is not a VAT number; the VAT number appends "01".
  defp repairs("SE", <<_::binary-size(10)>> = number), do: [number, number <> "01"]
  defp repairs(_country, number), do: [number]

  defp strip_prefix(number, country) do
    prefix = if country == "EL", do: ["EL", "GR"], else: [country]

    case Enum.find(prefix, &String.starts_with?(number, &1)) do
      nil -> number
      found -> String.replace_prefix(number, found, "")
    end
  end

  defp foreign_prefix(country, <<prefix::binary-size(2), rest::binary>>) do
    other = CountryCodes.normalize(prefix)

    if other != country and Map.has_key?(@formats, other) and validate(other, rest) == :ok do
      [{:country, other, rest}]
    else
      []
    end
  end

  defp foreign_prefix(_country, _number), do: []

  defp luhn_valid?(digits) do
    if Regex.match?(~r/^\d+$/, digits) do
      sum =
        digits
        |> String.to_charlist()
        |> Enum.reverse()
        |> Enum.with_index()
        |> Enum.reduce(0, fn {char, index}, acc -> acc + luhn_digit(char - ?0, index) end)

      rem(sum, 10) == 0
    else
      false
    end
  end

  defp luhn_digit(digit, index) when rem(index, 2) == 1 and digit * 2 > 9, do: digit * 2 - 9
  defp luhn_digit(digit, index) when rem(index, 2) == 1, do: digit * 2
  defp luhn_digit(digit, _index), do: digit
end
