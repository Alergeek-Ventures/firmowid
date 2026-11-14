defmodule Firmowid.Core.NipTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Firmowid.Core.Nip

  @weights [6, 5, 7, 2, 3, 4, 5, 6, 7]

  # Independent implementation of the official algorithm: the weighted sum of the
  # first nine digits mod 11 is the control digit; a remainder of 10 is not allowed.
  defp control_digit(digits) do
    digits |> Enum.zip(@weights) |> Enum.map(fn {d, w} -> d * w end) |> Enum.sum() |> rem(11)
  end

  defp valid_nip_digits do
    0..9
    |> integer()
    |> List.duplicate(9)
    |> fixed_list()
    |> filter(&(control_digit(&1) < 10))
    |> map(&(&1 ++ [control_digit(&1)]))
  end

  property "accepts every number with a correct control digit" do
    check all(digits <- valid_nip_digits()) do
      assert Nip.valid?(Enum.join(digits))
    end
  end

  property "accepts a valid number written with dashes and spaces" do
    check all(digits <- valid_nip_digits()) do
      [a, b, c, d, e] = digits |> Enum.chunk_every(2) |> Enum.map(&Enum.join/1)

      assert Nip.valid?("#{a}#{b}-#{c}-#{d} #{e}")
    end
  end

  # Every weight is coprime with 11 and a digit changes by 1..9, so no single-digit
  # error can leave the weighted sum unchanged mod 11.
  property "rejects a valid number with one digit changed" do
    check all(
            digits <- valid_nip_digits(),
            index <- integer(0..9),
            shift <- integer(1..9)
          ) do
      changed = List.update_at(digits, index, &rem(&1 + shift, 10))

      refute Nip.valid?(Enum.join(changed))
    end
  end

  property "rejects text that does not contain exactly ten digits" do
    check all(
            text <- string(:ascii),
            text |> String.replace(~r/\D/, "") |> String.length() != 10
          ) do
      refute Nip.valid?(text)
    end
  end
end
