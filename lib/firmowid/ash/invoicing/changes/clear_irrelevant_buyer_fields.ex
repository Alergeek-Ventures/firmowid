defmodule Firmowid.Ash.Invoicing.Changes.ClearIrrelevantBuyerFields do
  @moduledoc """
  Ash change that clears fields irrelevant to the selected buyer type.

  When switching from company to individual, clears company-specific fields.
  When switching from individual to company, clears individual-specific fields.
  Only acts on actual type transitions, not on every update.

  ## Options

    * `:type_field` — atom (`:buyer_type` or `:type`)
    * `:company_fields` — list of atoms to clear when switching to individual
      (e.g. `[:buyer_id, :buyer_full_name]` or `[:tax_id, :full_name]`)
    * `:individual_fields` — list of atoms to clear when switching to company
      (e.g. `[:buyer_pesel, :buyer_given_name, :buyer_surname]` or `[:pesel, :given_name, :surname]`)
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, opts, _context) do
    type_field = opts[:type_field]

    if Ash.Changeset.changing_attribute?(changeset, type_field) do
      clear_fields_for_type(changeset, opts)
    else
      changeset
    end
  end

  @impl true
  def atomic(changeset, opts, _context) do
    if Ash.Changeset.changing_attribute?(changeset, opts[:type_field]) do
      {:atomic, atomic_changes(opts)}
    else
      {:ok, changeset}
    end
  end

  defp clear_fields_for_type(changeset, opts) do
    type_field = opts[:type_field]
    company_fields = opts[:company_fields] || []
    individual_fields = opts[:individual_fields] || []

    case Ash.Changeset.get_attribute(changeset, type_field) do
      :individual -> clear_attributes(changeset, company_fields)
      :company -> clear_attributes(changeset, individual_fields)
      _ -> changeset
    end
  end

  defp clear_attributes(changeset, fields) do
    Enum.reduce(fields, changeset, fn field, cs ->
      Ash.Changeset.force_change_attribute(cs, field, nil)
    end)
  end

  defp atomic_changes(opts) do
    type_field = opts[:type_field]
    company_fields = opts[:company_fields] || []
    individual_fields = opts[:individual_fields] || []

    company_clears =
      Map.new(
        company_fields,
        &{&1, expr(if ^atomic_ref(type_field) == :individual, do: nil, else: ^atomic_ref(&1))}
      )

    individual_clears =
      Map.new(
        individual_fields,
        &{&1, expr(if ^atomic_ref(type_field) == :company, do: nil, else: ^atomic_ref(&1))}
      )

    Map.merge(company_clears, individual_clears)
  end
end
