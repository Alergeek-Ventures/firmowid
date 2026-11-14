defmodule Firmowid.Core.Validations.ValidateIbanTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Firmowid.Core.Member
  alias Firmowid.Core.Validations.ValidateIban

  @alphanumeric Enum.concat(?A..?Z, ?0..?9)

  defp validate(value) do
    Member
    |> Ash.Changeset.new()
    |> Ash.Changeset.force_change_attribute(:bank_account_number, value)
    |> ValidateIban.validate([], %{})
  end

  # ISO 13616 check digits, computed independently of the validator: turn the
  # letters into numbers (A = 10 ... Z = 35), read the whole thing as one integer
  # and take 98 minus its remainder mod 97.
  defp check_digits(country, bban) do
    remainder = rem(to_number(bban <> country <> "00"), 97)

    (98 - remainder) |> Integer.to_string() |> String.pad_leading(2, "0")
  end

  defp to_number(text) do
    text
    |> String.to_charlist()
    |> Enum.map_join(fn char ->
      if char in ?A..?Z, do: Integer.to_string(char - ?A + 10), else: <<char>>
    end)
    |> String.to_integer()
  end

  defp valid_iban do
    gen all(
          country <- string(?A..?Z, length: 2),
          bban <- string(@alphanumeric, min_length: 11, max_length: 30)
        ) do
      country <> check_digits(country, bban) <> bban
    end
  end

  property "accepts every IBAN with correct check digits" do
    check all(iban <- valid_iban()) do
      assert validate(iban) == :ok
    end
  end

  property "accepts an IBAN typed in lowercase and grouped with spaces" do
    check all(iban <- valid_iban()) do
      grouped =
        iban |> String.downcase() |> String.graphemes() |> Enum.chunk_every(4) |> Enum.join(" ")

      assert validate(grouped) == :ok
    end
  end

  # A digit replaced by another digit changes the number by delta * 10^k with
  # 0 < |delta| < 10, and 10 is coprime with the prime 97, so the remainder
  # mod 97 cannot stay the same. Digit-to-letter swaps change the number's
  # length and are not covered by this guarantee.
  property "rejects a valid IBAN with one digit changed" do
    check all(
            iban <- valid_iban(),
            index <- member_of(digit_positions(iban)),
            shift <- integer(1..9)
          ) do
      changed =
        iban
        |> String.to_charlist()
        |> List.update_at(index, fn digit -> rem(digit - ?0 + shift, 10) + ?0 end)
        |> List.to_string()

      assert {:error, field: :bank_account_number, message: _} = validate(changed)
    end
  end

  property "rejects a number whose length is outside 15 to 34 characters" do
    check all(
            # With the 4-character prefix: 5..14 and 35..64 characters.
            length <- one_of([integer(1..10), integer(31..60)]),
            tail <- string(@alphanumeric, length: length)
          ) do
      assert {:error, field: :bank_account_number, message: _} = validate("PL00" <> tail)
    end
  end

  property "rejects a valid IBAN with a foreign character inserted" do
    check all(
            iban <- valid_iban(),
            index <- integer(0..byte_size(iban)),
            char <- member_of(~c"-_!.,/#*")
          ) do
      {head, tail} = String.split_at(iban, index)

      assert {:error, field: :bank_account_number, message: _} =
               validate(head <> <<char>> <> tail)
    end
  end

  defp digit_positions(iban) do
    for {char, index} <- iban |> String.to_charlist() |> Enum.with_index(),
        char in ?0..?9,
        do: index
  end
end
