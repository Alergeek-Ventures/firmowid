defmodule FirmowidWeb.Infrastructure.Utilities.PolishQuantityTest do
  use ExUnit.Case, async: true

  alias FirmowidWeb.Infrastructure.Utilities.PolishQuantity

  doctest PolishQuantity

  test "uses plural form for teen endings" do
    assert PolishQuantity.quantity(12, "jabłko", "jabłka", "jabłek") == "12 jabłek"
    assert PolishQuantity.quantity(14, "jabłko", "jabłka", "jabłek") == "14 jabłek"
    assert PolishQuantity.quantity(112, "jabłko", "jabłka", "jabłek") == "112 jabłek"
  end

  test "uses paucal form after non-teen values ending in two through four" do
    assert PolishQuantity.quantity(2, "jabłko", "jabłka", "jabłek") == "2 jabłka"
    assert PolishQuantity.quantity(24, "jabłko", "jabłka", "jabłek") == "24 jabłka"
  end

  test "uses plural form for zero and values ending in other digits" do
    assert PolishQuantity.quantity(0, "jabłko", "jabłka", "jabłek") == "0 jabłek"
    assert PolishQuantity.quantity(5, "jabłko", "jabłka", "jabłek") == "5 jabłek"
  end
end
