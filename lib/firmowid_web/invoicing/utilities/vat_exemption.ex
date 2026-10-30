defmodule FirmowidWeb.Invoicing.Utilities.VatExemption do
  @moduledoc """
  Presentation layer for VAT exemption types.

  Provides select-specific labels
  for form inputs. Delegates to `Firmowid.Invoicing.VatExemption` for validation
  and business logic.
  """

  use Gettext, backend: Firmowid.Gettext

  alias Firmowid.Invoicing.VatExemption

  @select_options [
    {gettext_noop("Art. 113 sec. 1 and 9 (turnover limit of up to PLN 200 thousand)"), :art_113},
    {gettext_noop("Art. 43 sec. 1 (exemption based on the type of services)"), :art_43},
    {gettext_noop("Art. 82 sec. 3 (regulations of the Minister of Finance)"), :art_82_ust_3},
    {gettext_noop("Directive 2006/112/EC (EU transactions)"), :directive_2006_112},
    {gettext_noop("Other legal basis"), :other}
  ]

  @doc """
  Returns the select options for VAT exemption legal bases.
  """
  @spec options() :: [{String.t(), atom()}]
  def options do
    Enum.map(@select_options, fn {label, type} ->
      {Gettext.gettext(Firmowid.Gettext, label), type}
    end)
  end

  @doc """
  Returns the display label for an exemption legal basis.
  """
  @spec label(atom()) :: String.t() | nil
  def label(type), do: VatExemption.label(type)
end
