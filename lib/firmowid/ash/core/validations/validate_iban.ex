defmodule Firmowid.Ash.Core.Validations.ValidateIban do
  @moduledoc """
  Ash validation for bank account numbers (IBANs).

  Validates the IBAN layout, the total length bounds, and the ISO 7064 mod-97
  checksum. Per-country BBAN lengths from the IBAN registry are intentionally
  not enforced — the mod-97 check already rejects mistyped numbers.
  """
  use Ash.Resource.Validation

  @min_length 15
  @max_length 34

  @impl true
  def validate(changeset, opts, _context) do
    field = opts[:field] || :bank_account_number

    case Ash.Changeset.get_attribute(changeset, field) do
      value when is_binary(value) and value != "" ->
        if valid?(value) do
          :ok
        else
          {:error, field: field, message: "musi być poprawnym numerem konta bankowego (IBAN)"}
        end

      _ ->
        :ok
    end
  end

  @impl true
  def atomic(changeset, opts, context) do
    validate(changeset, opts, context)
  end

  defp valid?(value) do
    with iban when is_binary(iban) <- normalize(value),
         true <- Regex.match?(~r/\A[A-Z]{2}\d{2}[A-Z0-9]{1,30}\z/, iban),
         true <- byte_size(iban) in @min_length..@max_length do
      mod_97(iban) == 1
    else
      _ -> false
    end
  end

  defp normalize(value) do
    case String.replace(value, ~r/\p{White_Space}/u, "") do
      "" -> nil
      stripped -> String.upcase(stripped)
    end
  end

  # ISO 7064 mod-97-10: move the first four characters to the end, replace each
  # letter with its two-digit position (A = 10 ... Z = 35), then reduce mod 97.
  defp mod_97(<<head::binary-size(4), tail::binary>>) do
    <<tail::binary, head::binary>>
    |> to_charlist()
    |> Enum.reduce(0, fn char, acc ->
      if char in ?A..?Z do
        rem(acc * 100 + (char - ?A + 10), 97)
      else
        rem(acc * 10 + (char - ?0), 97)
      end
    end)
  end
end
