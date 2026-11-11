defmodule Firmowid.Invoicing.Validations.ValidateEuVatNumber do
  @moduledoc """
  Rejects a buyer EU VAT number that breaks its country's structure or checksum.

  `ValidateTaxId` keeps the KSeF schema pattern on every action; this validation
  adds the national rules from `EuVatNumber` where a number is issued or saved for
  reuse. It says nothing about registration, which only VIES confirms.

  A correction has to repeat the buyer number of the invoice it corrects (see
  `InvoiceRenderer.validate_correction_buyer_tax_id!/1`), which is how an invoice
  issued with a wrong number is corrected to zero before a new one is issued. With
  `:confirmation_argument`, such a correction passes once the user confirms it.

  ## Options

    * `:id_field`, `:country_field`, `:pesel_field`, `:type_field` — as in `ValidateTaxId`,
      defaulting to the invoice buyer fields
    * `:confirmation_argument` — optional boolean argument accepting the corrected invoice's number
  """
  use Ash.Resource.Validation
  use Gettext, backend: Firmowid.Gettext

  alias Firmowid.Invoicing.CountryCodes
  alias Firmowid.Invoicing.EuVatNumber

  @buyer_fields [
    id_field: :buyer_id,
    country_field: :buyer_country,
    pesel_field: :buyer_pesel,
    type_field: :buyer_type
  ]

  @impl true
  def init(opts), do: {:ok, Keyword.merge(@buyer_fields, opts)}

  @impl true
  def validate(changeset, opts, _context) do
    country = Ash.Changeset.get_attribute(changeset, opts[:country_field])
    number = Ash.Changeset.get_attribute(changeset, opts[:id_field])
    pesel = Ash.Changeset.get_attribute(changeset, opts[:pesel_field])
    type = Ash.Changeset.get_attribute(changeset, opts[:type_field])

    with :eu_vat <- CountryCodes.tax_id_type(country, pesel, type),
         {:error, rule, _suggestions} <- EuVatNumber.check(country, number) do
      reject(changeset, opts, rule, country)
    else
      _valid_or_not_applicable -> :ok
    end
  end

  # The national rules and checksums run in Elixir; an atomic update would hand them
  # SQL expressions instead of the new values.
  @impl true
  def atomic(_changeset, _opts, _context), do: {:not_atomic, "EU VAT number rules need the submitted values"}

  # Ash turns the error's other keys into its message vars.
  defp reject(changeset, opts, rule, country) do
    vars = [
      country: CountryCodes.country_name(CountryCodes.normalize(country)),
      pattern: EuVatNumber.pattern(country)
    ]

    case opts[:confirmation_argument] do
      nil ->
        {:error, [field: opts[:id_field], message: message(rule)] ++ vars}

      argument ->
        if Ash.Changeset.get_argument(changeset, argument) == true do
          :ok
        else
          message =
            gettext_noop(
              "The corrected invoice has a buyer VAT number that does not match the %{country} format (%{pattern}). The correction must repeat it: confirm that you are correcting that invoice and issue a new one with the right number."
            )

          {:error, [field: argument, message: message] ++ vars}
        end
    end
  end

  defp message(:format), do: gettext_noop("does not match the %{country} VAT number format (%{pattern})")

  defp message(:checksum), do: gettext_noop("has an invalid check digit for a %{country} VAT number")
end
