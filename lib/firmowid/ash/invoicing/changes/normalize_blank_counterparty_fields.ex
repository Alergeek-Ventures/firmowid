defmodule Firmowid.Ash.Invoicing.Changes.NormalizeBlankCounterpartyFields do
  @moduledoc """
  Normalizes blank counterparty fields to `nil` before validation and identity checks.

  This keeps Ash identities declarative, without partial-index SQL mirrors for
  fields that may arrive from forms as empty strings.
  """
  use Ash.Resource.Change

  alias Firmowid.Ash.Core.Pesel

  @impl true
  def change(changeset, _opts, _context) do
    changeset =
      Enum.reduce(
        [:tax_id, :country, :mail_address, :mail_country, :full_name, :given_name, :surname],
        changeset,
        fn field, acc ->
          case Ash.Changeset.get_attribute(acc, field) do
            value when is_binary(value) ->
              case String.trim(value) do
                "" -> Ash.Changeset.force_change_attribute(acc, field, nil)
                trimmed -> Ash.Changeset.force_change_attribute(acc, field, trimmed)
              end

            _other ->
              acc
          end
        end
      )

    changeset =
      case Ash.Changeset.get_attribute(changeset, :pesel) do
        value when is_binary(value) ->
          Ash.Changeset.force_change_attribute(changeset, :pesel, Pesel.normalize(value))

        _other ->
          changeset
      end

    case Ash.Changeset.get_attribute(changeset, :is_different_mail_address) do
      true ->
        changeset

      _other ->
        changeset
        |> Ash.Changeset.force_change_attribute(:mail_address, nil)
        |> Ash.Changeset.force_change_attribute(:mail_country, nil)
    end
  end

  @impl true
  def atomic(_changeset, _opts, _context) do
    {:atomic,
     %{
       tax_id: normalize_blank(:tax_id),
       country: normalize_blank(:country),
       pesel: normalize_pesel(:pesel),
       full_name: normalize_blank(:full_name),
       given_name: normalize_blank(:given_name),
       surname: normalize_blank(:surname),
       mail_address: normalize_mail_field(:mail_address),
       mail_country: normalize_mail_field(:mail_country)
     }}
  end

  defp normalize_blank(field) do
    expr(
      cond do
        is_nil(^atomic_ref(field)) -> nil
        string_trim(^atomic_ref(field)) == "" -> nil
        true -> string_trim(^atomic_ref(field))
      end
    )
  end

  defp normalize_mail_field(field) do
    expr(
      cond do
        ^atomic_ref(:is_different_mail_address) != true -> nil
        is_nil(^atomic_ref(field)) -> nil
        string_trim(^atomic_ref(field)) == "" -> nil
        true -> string_trim(^atomic_ref(field))
      end
    )
  end

  defp normalize_pesel(field) do
    expr(
      cond do
        is_nil(^atomic_ref(field)) -> nil
        string_trim(^atomic_ref(field)) == "" -> nil
        true -> fragment("nullif(regexp_replace(?, '\\D', '', 'g'), '')", ^atomic_ref(field))
      end
    )
  end
end
