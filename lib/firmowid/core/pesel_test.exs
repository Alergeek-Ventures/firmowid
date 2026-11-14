defmodule Firmowid.Core.PeselTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Firmowid.Core.Pesel

  @weights [1, 3, 7, 9, 1, 3, 7, 9, 1, 3]

  # Independent implementation of the official algorithm: the control digit
  # completes the weighted sum of the first ten digits to a multiple of 10.
  defp control_digit(digits) do
    sum = digits |> Enum.zip(@weights) |> Enum.map(fn {d, w} -> d * w end) |> Enum.sum()

    rem(10 - rem(sum, 10), 10)
  end

  defp valid_pesel_digits do
    0..9
    |> integer()
    |> List.duplicate(10)
    |> fixed_list()
    |> map(&(&1 ++ [control_digit(&1)]))
  end

  property "accepts every number with a correct control digit" do
    check all(digits <- valid_pesel_digits()) do
      assert Pesel.valid?(Enum.join(digits))
    end
  end

  property "accepts a valid number written with spaces" do
    check all(digits <- valid_pesel_digits()) do
      {head, tail} = digits |> Enum.join() |> String.split_at(6)

      assert Pesel.valid?("#{head} #{tail}")
    end
  end

  # Every weight is coprime with 10 and a digit changes by 1..9, so no single-digit
  # error can leave the weighted sum unchanged mod 10.
  property "rejects a valid number with one digit changed" do
    check all(
            digits <- valid_pesel_digits(),
            index <- integer(0..10),
            shift <- integer(1..9)
          ) do
      changed = List.update_at(digits, index, &rem(&1 + shift, 10))

      refute Pesel.valid?(Enum.join(changed))
    end
  end

  property "rejects text that does not contain exactly eleven digits" do
    check all(
            text <- string(:ascii),
            text |> String.replace(~r/\D/, "") |> String.length() != 11
          ) do
      refute Pesel.valid?(text)
    end
  end
end
