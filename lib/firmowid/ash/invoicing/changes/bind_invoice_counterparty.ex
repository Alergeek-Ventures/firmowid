defmodule Firmowid.Ash.Invoicing.Changes.BindInvoiceCounterparty do
  @moduledoc "Binds a same-organization counterparty without altering the invoice buyer snapshot."
  use Ash.Resource.Change
  use Gettext, backend: Firmowid.Gettext

  alias Firmowid.Ash.Invoicing.Counterparty
  alias Firmowid.Ash.Invoicing.IdentifierNormalization

  require Ash.Query

  @doc "Validates an explicit counterparty or attaches a matching tenant-scoped record."
  @spec change(Ash.Changeset.t(), keyword(), Ash.Resource.Change.Context.t()) :: Ash.Changeset.t()
  @impl true
  def change(changeset, _opts, context) do
    opts = Ash.Context.to_opts(context)

    case Ash.Changeset.get_attribute(changeset, :counterparty_id) do
      nil -> bind_matching_counterparty(changeset, opts)
      id -> validate_explicit_counterparty(changeset, id, opts)
    end
  end

  defp validate_explicit_counterparty(changeset, id, opts) do
    case Counterparty.get(id, opts) do
      {:ok, %Counterparty{}} -> changeset
      {:ok, nil} -> invalid_counterparty(changeset)
      {:error, error} -> Ash.Changeset.add_error(changeset, error)
    end
  end

  defp invalid_counterparty(changeset) do
    Ash.Changeset.add_error(changeset,
      field: :counterparty_id,
      message: gettext("Counterparty must belong to the current organization.")
    )
  end

  defp bind_matching_counterparty(changeset, opts) do
    tax_id =
      IdentifierNormalization.normalize_tax_id(Ash.Changeset.get_attribute(changeset, :buyer_id))

    country = Ash.Changeset.get_attribute(changeset, :buyer_country)
    buyer_type = Ash.Changeset.get_attribute(changeset, :buyer_type)

    if tax_id in [nil, ""] do
      changeset
    else
      identifiers = matching_identifiers(tax_id, country)

      query =
        Ash.Query.filter(
          Counterparty,
          (normalized_tax_id in ^identifiers or
             (is_nil(normalized_tax_id) and
                fragment(
                  "nullif(regexp_replace(upper(coalesce(?, '')), '[^0-9A-Z]', '', 'g'), '')",
                  tax_id
                ) in ^identifiers)) and
            country == ^country and type == ^buyer_type
        )

      case Counterparty.list(%{status: :all}, Keyword.put(opts, :query, query)) do
        {:ok, [counterparty]} ->
          Ash.Changeset.force_change_attribute(changeset, :counterparty_id, counterparty.id)

        {:ok, _empty_or_ambiguous} ->
          changeset

        {:error, error} ->
          Ash.Changeset.add_error(changeset, error)
      end
    end
  end

  # TaxId.normalize/1 retains the PL prefix, while Polish NIP validation accepts it.
  # Existing counterparties may store either spelling, so compare both canonical forms.
  defp matching_identifiers("PL" <> digits = tax_id, "PL"), do: [tax_id, digits]
  defp matching_identifiers(tax_id, "PL"), do: [tax_id, "PL" <> tax_id]
  defp matching_identifiers(tax_id, _country), do: [tax_id]
end
