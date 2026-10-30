defmodule Firmowid.Core.Validations.ValidateNip do
  @moduledoc """
  Ash validation for Polish NIP values using shared checksum rules.
  """
  use Ash.Resource.Validation
  use Gettext, backend: Firmowid.Gettext

  alias Firmowid.Core.Nip

  @impl true
  def validate(changeset, opts, _context) do
    field = opts[:field] || :nip

    case Ash.Changeset.get_attribute(changeset, field) do
      nip when is_binary(nip) and nip != "" ->
        if Nip.valid?(nip) do
          :ok
        else
          {:error, field: field, message: gettext_noop("must be a valid NIP number")}
        end

      _ ->
        :ok
    end
  end

  @impl true
  def atomic(changeset, opts, context) do
    validate(changeset, opts, context)
  end
end
