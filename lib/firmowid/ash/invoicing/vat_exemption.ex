defmodule Firmowid.Ash.Invoicing.VatExemption do
  @moduledoc """
  VAT exemption types and legal basis labels per Polish VAT law.

  ## Exemption Types

    * `:art_113` — Art. 113 ust. 1 i 9 ustawy o VAT (small business exemption)
    * `:art_43` — Art. 43 ust. 1 ustawy o VAT (specific exempt activities)
    * `:art_82_ust_3` — Przepisy wydane na podstawie art. 82 ust. 3 ustawy o VAT
    * `:directive_2006_112` — Dyrektywa 2006/112/WE (EU directive)
    * `:other` — Inna podstawa prawna (requires free-text `vat_exemption_basis`)

  When `:other` is selected, `vat_exemption_basis` must be provided.
  For all other types, `vat_exemption_basis` is cleared to `nil`.
  """

  @type exemption_type ::
          :art_113 | :art_43 | :art_82_ust_3 | :directive_2006_112 | :other

  @valid_types [:art_113, :art_43, :art_82_ust_3, :directive_2006_112, :other]

  @labels %{
    art_113: "Art. 113 ust. 1 i 9 ustawy o VAT",
    art_43: "Art. 43 ust. 1 ustawy o VAT",
    art_82_ust_3: "Przepisy wydane na podstawie art. 82 ust. 3 ustawy o VAT",
    directive_2006_112: "Dyrektywa 2006/112/WE",
    other: "Inna podstawa prawna"
  }

  @doc """
  Returns list of all valid VAT exemption types.
  """
  @spec valid_types() :: [exemption_type()]
  def valid_types, do: @valid_types

  @doc """
  Checks if the given type is a valid VAT exemption type.
  """
  @spec valid?(exemption_type()) :: boolean()
  def valid?(type), do: type in @valid_types

  @doc """
  Returns the display label for an exemption type.
  """
  @spec label(exemption_type()) :: String.t()
  def label(type) do
    Map.get(@labels, type, "Inna podstawa prawna")
  end

  @doc """
  Returns the full legal-basis label for an exemption type.

  For `:other`, returns the free-text basis from the invoice/resource,
  falling back to the `:art_113` label when empty.
  """
  @spec basis_label(exemption_type(), map()) :: String.t()
  def basis_label(:other, resource) do
    case resource do
      %{vat_exemption_basis: basis} when is_binary(basis) and basis != "" ->
        basis

      _ ->
        @labels[:art_113]
    end
  end

  def basis_label(type, _resource) when type in @valid_types do
    @labels[type] || @labels[:art_113]
  end

  def basis_label(_type, _resource), do: @labels[:art_113]

  @doc """
  Returns true if the given type requires a free-text legal basis.
  """
  @spec requires_basis?(exemption_type()) :: boolean()
  def requires_basis?(:other), do: true
  def requires_basis?(_), do: false
end
