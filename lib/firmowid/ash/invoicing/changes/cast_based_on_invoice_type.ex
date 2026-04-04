defmodule Firmowid.Ash.Invoicing.Changes.CastBasedOnInvoiceType do
  @moduledoc """
  Ash change that enforces field constraints based on invoice type.

  When `invoice_type` changes to `:poland`, forces `currency` to `"PLN"`
  and `is_reverse_charge` to `false`.

  When `invoice_type` changes to `:foreign`, forces `is_cash_account` to `false`
  (only if the resource has that attribute — WizardDraft does not).

  Only acts on actual `invoice_type` changes, not on every update.
  """
  use Ash.Resource.Change

  alias Ash.Resource.Info

  @impl true
  def change(changeset, _opts, _context) do
    if Ash.Changeset.changing_attribute?(changeset, :invoice_type) do
      apply_invoice_type_constraints(changeset)
    else
      changeset
    end
  end

  defp apply_invoice_type_constraints(changeset) do
    case Ash.Changeset.get_attribute(changeset, :invoice_type) do
      :poland ->
        changeset
        |> Ash.Changeset.force_change_attribute(:currency, "PLN")
        |> Ash.Changeset.force_change_attribute(:is_reverse_charge, false)

      :foreign ->
        maybe_clear_cash_account(changeset)

      _ ->
        changeset
    end
  end

  defp maybe_clear_cash_account(changeset) do
    if Info.attribute(changeset.resource, :is_cash_account) do
      Ash.Changeset.force_change_attribute(changeset, :is_cash_account, false)
    else
      changeset
    end
  end
end
