defmodule FirmowidWeb.Infrastructure.Utilities.PolishQuantity do
  @moduledoc """
  Formats integer quantities using Polish noun declension rules.
  """

  @doc """
  Formats a quantity with its singular, plural-few, or plural-many noun form.

  ## Examples

      iex> FirmowidWeb.Infrastructure.Utilities.PolishQuantity.quantity(1, "jabłko", "jabłka", "jabłek")
      "1 jabłko"

      iex> FirmowidWeb.Infrastructure.Utilities.PolishQuantity.quantity(22, "jabłko", "jabłka", "jabłek")
      "22 jabłka"
  """
  @spec quantity(integer(), String.t(), String.t(), String.t()) :: String.t()
  def quantity(value, singular, plural_few, plural_many) when is_integer(value) do
    "#{value} #{noun_form(value, singular, plural_few, plural_many)}"
  end

  defp noun_form(value, singular, _plural_few, _plural_many) when abs(value) == 1, do: singular

  defp noun_form(value, _singular, _plural_few, plural_many) when rem(abs(value), 100) in 12..14, do: plural_many

  defp noun_form(value, _singular, plural_few, _plural_many) when rem(abs(value), 10) in 2..4, do: plural_few

  defp noun_form(_value, _singular, _plural_few, plural_many), do: plural_many
end
