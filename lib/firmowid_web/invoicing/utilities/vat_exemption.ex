defmodule FirmowidWeb.Invoicing.Utilities.VatExemption do
  @moduledoc """
  Presentation layer for VAT exemption types.

  Provides select-specific labels
  for form inputs. Delegates to `Firmowid.Ash.Invoicing.VatExemption` for validation
  and business logic.
  """

  alias Firmowid.Ash.Invoicing.VatExemption

  @select_options [
    {"Art. 113 ust. 1 i 9 (limit obrotów do 200 tys. zł)", :art_113},
    {"Art. 43 ust. 1 (zwolnienie ze względu na rodzaj usług)", :art_43},
    {"Art. 82 ust. 3 (rozporządzenia Ministra Finansów)", :art_82_ust_3},
    {"Dyrektywa 2006/112/WE (transakcje unijne)", :directive_2006_112},
    {"Inna podstawa prawna", :other}
  ]

  @doc """
  Returns the select options for VAT exemption legal bases.
  """
  @spec options() :: [{String.t(), atom()}]
  def options, do: @select_options

  @doc """
  Returns the display label for an exemption legal basis.
  """
  @spec label(atom()) :: String.t() | nil
  def label(type), do: VatExemption.label(type)
end
