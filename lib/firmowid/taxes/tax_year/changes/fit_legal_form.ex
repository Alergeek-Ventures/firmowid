defmodule Firmowid.Taxes.TaxYear.Changes.FitLegalForm do
  @moduledoc """
  Checks a tax year against its organization: the legal form must be answered,
  CIT settings belong only to a limited company, the VAT period only to a VAT
  payer, and the partners must fit the legal form and share the whole profit.

  The organization is read through the actor's own scope, never from input. The
  fields are checked while the changeset is built, so a form shows these errors
  together with the partners' own. Partners are checked after they are saved, so
  the check sees the complete, cast list that the action left; an error rolls
  the whole action back.
  """
  use Ash.Resource.Change
  use Gettext, backend: Firmowid.Gettext

  alias Ash.Error.Changes.InvalidArgument
  alias Firmowid.Core

  @hundred Decimal.new(100)

  @impl true
  def change(changeset, _opts, context) do
    organization = Core.get_organization!(changeset.tenant, Ash.Context.to_opts(context))

    changeset
    |> check_legal_form(organization.legal_form)
    |> check_cit(organization.legal_form == :limited_company)
    |> check_vat_period(organization.is_vat_payer)
    |> Ash.Changeset.after_action(fn _changeset, tax_year ->
      check_partners(tax_year, organization.legal_form, context)
    end)
  end

  defp check_legal_form(changeset, nil),
    do: add_error(changeset, :year, gettext_noop("Choose the company's legal form in the company settings first."))

  defp check_legal_form(changeset, _legal_form), do: changeset

  defp check_cit(changeset, true) do
    changeset
    |> require_present(:cit_rate, gettext_noop("Choose the CIT rate."))
    |> require_present(:cit_advances, gettext_noop("Choose how CIT advances are paid."))
  end

  defp check_cit(changeset, false) do
    changeset
    |> require_absent(:cit_rate, gettext_noop("Only a limited company pays CIT."))
    |> require_absent(:cit_advances, gettext_noop("Only a limited company pays CIT."))
  end

  defp check_vat_period(changeset, true),
    do: require_present(changeset, :vat_period, gettext_noop("Choose how often VAT is settled."))

  defp check_vat_period(changeset, false),
    do: require_absent(changeset, :vat_period, gettext_noop("Only a VAT payer settles VAT."))

  defp require_present(changeset, field, message) do
    if is_nil(Ash.Changeset.get_attribute(changeset, field)),
      do: add_error(changeset, field, message),
      else: changeset
  end

  defp require_absent(changeset, field, message) do
    if is_nil(Ash.Changeset.get_attribute(changeset, field)),
      do: changeset,
      else: add_error(changeset, field, message)
  end

  defp add_error(changeset, field, message), do: Ash.Changeset.add_error(changeset, field: field, message: message)

  defp check_partners(tax_year, legal_form, context) do
    with {:ok, %{partners: partners}} <-
           Ash.load(tax_year, :partners, Ash.Context.to_opts(context)) do
      case partners_error(legal_form, partners) do
        nil -> {:ok, tax_year}
        message -> {:error, InvalidArgument.exception(field: :partners, message: message)}
      end
    end
  end

  defp partners_error(:limited_company, []), do: nil

  defp partners_error(:limited_company, _partners),
    do: gettext_noop("A limited company pays CIT itself and has no partners paying their own income tax.")

  defp partners_error(:sole_proprietorship, [_owner] = partners), do: shares_error(partners)

  defp partners_error(:sole_proprietorship, _partners), do: gettext_noop("A sole proprietorship has exactly one owner.")

  defp partners_error(:civil_partnership, [_first, _second | _rest] = partners), do: shares_error(partners)

  defp partners_error(:civil_partnership, _partners), do: gettext_noop("A civil partnership has at least two partners.")

  defp shares_error(partners) do
    total = partners |> Enum.map(& &1.profit_share) |> Enum.reduce(Decimal.new(0), &Decimal.add/2)

    if Decimal.equal?(total, @hundred),
      do: nil,
      else: gettext_noop("The partners' profit shares must add up to 100%.")
  end
end
