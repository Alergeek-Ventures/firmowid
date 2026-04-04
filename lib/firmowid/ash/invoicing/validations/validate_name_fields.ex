defmodule Firmowid.Ash.Invoicing.Validations.ValidateNameFields do
  @moduledoc """
  Ash validation that checks name field presence based on buyer/counterparty type.

  Companies require `full_name_field`, individuals require `given_name_field`
  and `surname_field`.

  ## Options

    * `:type_field` — atom (`:buyer_type` or `:type`)
    * `:full_name_field` — atom (`:buyer_full_name` or `:full_name`)
    * `:given_name_field` — atom (`:buyer_given_name` or `:given_name`)
    * `:surname_field` — atom (`:buyer_surname` or `:surname`)
  """
  use Ash.Resource.Validation

  @impl true
  def validate(changeset, opts, _context) do
    type_field = opts[:type_field]
    full_name_field = opts[:full_name_field]
    given_name_field = opts[:given_name_field]
    surname_field = opts[:surname_field]

    type = Ash.Changeset.get_attribute(changeset, type_field)

    case type do
      :company ->
        full_name = Ash.Changeset.get_attribute(changeset, full_name_field)

        if is_nil(full_name) or full_name == "" do
          {:error, field: full_name_field, message: "nazwa firmy jest wymagana"}
        else
          :ok
        end

      :individual ->
        given_name = Ash.Changeset.get_attribute(changeset, given_name_field)
        surname = Ash.Changeset.get_attribute(changeset, surname_field)

        errors =
          []
          |> maybe_add_error(given_name, given_name_field, "imię jest wymagane")
          |> maybe_add_error(surname, surname_field, "nazwisko jest wymagane")

        case errors do
          [] -> :ok
          errors -> {:error, errors}
        end

      _ ->
        :ok
    end
  end

  defp maybe_add_error(errors, value, field, message) do
    if is_nil(value) or value == "" do
      [{:error, field: field, message: message} | errors]
    else
      errors
    end
  end
end
