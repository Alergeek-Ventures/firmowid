defmodule FirmowidWeb.Invoicing.Components.EuVatSuggestions do
  @moduledoc """
  Fixes offered under an EU VAT number field when the number breaks its country's rules.

  Clicking one sends `apply_eu_vat_suggestion` with the corrected `number` and, when the
  number belongs to another member state, that `country`.
  """
  use FirmowidWeb, :html

  import FirmowidUI.Components.Button

  alias Firmowid.Invoicing.CountryCodes
  alias Firmowid.Invoicing.EuVatNumber

  attr :id, :string, required: true
  attr :country, :any, required: true
  attr :number, :any, required: true
  attr :class, :any, default: nil

  @doc "Renders the suggestions for the given buyer country and number, or nothing."
  @spec eu_vat_suggestions(map()) :: Phoenix.LiveView.Rendered.t()
  def eu_vat_suggestions(assigns) do
    assigns = assign(assigns, :suggestions, suggestions(assigns.country, assigns.number))

    ~H"""
    <ul :if={@suggestions != []} id={@id} class={["space-y-2", @class]}>
      <li
        :for={suggestion <- @suggestions}
        class="flex items-center justify-between gap-3 rounded-lg bg-rust-200 p-3 text-sm text-rust-700"
      >
        <span>{suggestion_text(suggestion)}</span>
        <.button
          type="button"
          size="small"
          variant="tertiary"
          phx-click="apply_eu_vat_suggestion"
          {suggestion_values(suggestion)}
        >
          {suggestion_action(suggestion)}
        </.button>
      </li>
    </ul>
    """
  end

  defp suggestions(country, number) when is_binary(country) and is_binary(number) do
    case EuVatNumber.check(country, number) do
      {:error, _rule, suggestions} -> suggestions
      _valid_or_not_applicable -> []
    end
  end

  defp suggestions(_country, _number), do: []

  defp suggestion_text({:number, number}), do: gettext("Did you mean %{number}?", number: number)

  defp suggestion_text({:country, country, number}),
    do:
      gettext("%{number} is a VAT number from %{country}.",
        number: country <> number,
        country: CountryCodes.country_name(country)
      )

  defp suggestion_action({:number, _number}), do: gettext("Use this number")
  defp suggestion_action({:country, _country, _number}), do: gettext("Change the country")

  defp suggestion_values({:number, number}), do: %{"phx-value-number" => number}

  defp suggestion_values({:country, country, number}), do: %{"phx-value-number" => number, "phx-value-country" => country}
end
