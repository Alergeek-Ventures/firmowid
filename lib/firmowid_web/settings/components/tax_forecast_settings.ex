defmodule FirmowidWeb.Settings.Components.TaxForecastSettings do
  @moduledoc """
  Organization-wide assumptions for the planned income tax reserve.

  The component reads the organization itself: the settings view keeps the
  organization from its mount, so a saved change must survive switching tabs.
  """
  use FirmowidWeb, :live_component

  import FirmowidUI.Components.Button
  import FirmowidWeb.Infrastructure.Hooks.RequireOrganization, only: [attach_access_hook: 2]

  alias Firmowid.Core
  alias Firmowid.Core.Organization
  alias Firmowid.Scope

  @impl true
  def mount(socket), do: {:ok, attach_access_hook(socket, :scope)}

  @impl true
  def update(%{current_user: user}, socket) do
    scope = Scope.new!(user, user.member.organization_id)
    organization = Core.get_organization!(scope.tenant, scope: scope)

    {:ok,
     socket
     |> assign(:scope, scope)
     |> assign(:editable?, Ash.can?({organization, :update_tax_forecast_settings}, scope))
     |> assign_organization(organization)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section id="rezerwa-podatkowa" class="space-y-4">
      <div class="space-y-2">
        <h2 class="text-base leading-none font-semibold text-grey-900">
          {gettext("Income tax reserve")}
        </h2>
        <p class="max-w-prose text-sm/snug text-grey-700">
          {gettext(
            "Firmowid does not know how your company is taxed, so it does not choose a rate for you. The reserve is a planning assumption, not a PIT or CIT rate, an advance payment or a tax return."
          )}
        </p>
      </div>

      <.form
        :if={@editable?}
        for={@form}
        id="tax-forecast-settings-form"
        phx-target={@myself}
        phx-submit="save"
        class="max-w-prose space-y-4"
      >
        <div class="flex flex-col gap-1">
          <label for={@form[:income_reserve_rate].id} class="text-sm/snug text-grey-700">
            {gettext("Reserve rate (%)")}
          </label>
          <.input
            field={@form[:income_reserve_rate]}
            type="number"
            min="0"
            max="100"
            step="0.01"
            class="w-32"
          />
          <p class="text-sm/snug text-grey-600">
            {gettext("Leave it empty to keep the income tax reserve unset.")}
          </p>
        </div>

        <div class="flex flex-col gap-1">
          <.input
            field={@form[:invoice_costs_deductible]}
            type="checkbox"
            label={gettext("Use recorded cost invoices as reserve costs")}
          />
          <p class="text-sm/snug text-grey-600">
            {gettext(
              "Each cost invoice counts with its payment amount less the deductible VAT recorded on it, including non-deductible VAT and settlement charges. These are not statutory tax-deductible costs. Bank costs without an invoice, payroll and tax adjustments are not included."
            )}
          </p>
        </div>

        <.button
          type="submit"
          variant="secondary"
          size="small"
          phx-disable-with={gettext("Saving...")}
        >
          {gettext("Save")}
        </.button>
      </.form>

      <div :if={!@editable?} class="space-y-3 text-sm/snug text-grey-700">
        <dl class="grid grid-cols-[auto_1fr] gap-x-5 gap-y-2">
          <dt>{gettext("Reserve rate")}</dt>
          <dd class="text-grey-900">{rate_text(@settings[:income_reserve_rate])}</dd>
          <dt>{gettext("Recorded cost invoices as reserve costs")}</dt>
          <dd class="text-grey-900">
            {if @settings[:invoice_costs_deductible] == true,
              do: pgettext("tax reserve cost assumption", "Accepted"),
              else: pgettext("tax reserve cost assumption", "Not accepted")}
          </dd>
        </dl>
        <p class="rounded-lg bg-grey-50 px-4 py-3">
          {gettext("Only an administrator can change the reserve assumptions.")}
        </p>
      </div>
    </section>
    """
  end

  @impl true
  def handle_event("save", %{"tax_forecast_settings" => params}, socket) do
    with {:ok, rate} <- parse_rate(params["income_reserve_rate"]),
         {:ok, organization} <-
           Organization.update_tax_forecast_settings(
             socket.assigns.organization,
             %{
               tax_forecast_settings: %{
                 income_reserve_rate: rate,
                 invoice_costs_deductible: params["invoice_costs_deductible"] == "true"
               }
             },
             scope: socket.assigns.scope
           ) do
      {:noreply,
       socket
       |> assign_organization(organization)
       |> put_flash(:info, gettext("Reserve assumptions saved."))}
    else
      :error ->
        {:noreply, assign(socket, :form, invalid_rate_form(params))}

      {:error, %Ash.Error.Invalid{}} ->
        {:noreply, assign(socket, :form, invalid_rate_form(params))}
    end
  end

  # The settings map is nil until the first save; an empty rate stays unset (nil), never 0.
  defp assign_organization(socket, organization) do
    settings = organization.tax_forecast_settings || %{}
    rate = settings[:income_reserve_rate]

    form =
      to_form(
        %{
          "income_reserve_rate" => rate && Decimal.to_string(rate, :normal),
          "invoice_costs_deductible" => settings[:invoice_costs_deductible] == true
        },
        as: :tax_forecast_settings
      )

    socket
    |> assign(:organization, organization)
    |> assign(:settings, settings)
    |> assign(:form, form)
  end

  defp invalid_rate_form(params) do
    to_form(params,
      as: :tax_forecast_settings,
      errors: [
        income_reserve_rate: {gettext("Enter a number from 0 to 100, or leave the field empty."), []}
      ]
    )
  end

  defp parse_rate(value) do
    case String.trim(value) do
      "" ->
        {:ok, nil}

      rate ->
        case Decimal.parse(rate) do
          {decimal, ""} -> {:ok, decimal}
          _invalid -> :error
        end
    end
  end

  defp rate_text(nil), do: pgettext("tax reserve rate", "Not set")

  # Shows the administrator's rate with its own precision, e.g. 19% or 8,5%.
  defp rate_text(rate) do
    rate
    |> Decimal.div(100)
    |> Firmowid.Cldr.Number.to_string!(
      format: :percent,
      fractional_digits: max(0, -Decimal.normalize(rate).exp)
    )
  end
end
