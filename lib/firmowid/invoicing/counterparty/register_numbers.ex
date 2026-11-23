defmodule Firmowid.Invoicing.Counterparty.RegisterNumbers do
  @moduledoc """
  A company counterparty's KRS and REGON numbers, typed by the user or taken from
  the VAT white list. KRS cannot be searched by NIP, so a KRS number lets the NIP
  check (`NipRegistration`) confirm an entity the white list does not know.
  """
  use Spark.Dsl.Fragment, of: Ash.Resource
  use Gettext, backend: Firmowid.Gettext

  # Only when changing: the atomic updates that record a check leave the numbers alone.
  validations do
    validate match(:krs, ~r/^\d{10}$/),
      where: [changing(:krs)],
      message: gettext_noop("must have 10 digits")

    validate match(:regon, ~r/^(\d{9}|\d{14})$/),
      where: [changing(:regon)],
      message: gettext_noop("must have 9 or 14 digits")
  end

  attributes do
    attribute :krs, :string, public?: true, description: "KRS number, 10 digits."
    attribute :regon, :string, public?: true, description: "REGON number, 9 or 14 digits."
  end
end
