defmodule FirmowidWeb.Delegations.Components.DelegationsList do
  @moduledoc "The employee's own business trips on their profile."

  use FirmowidWeb, :html

  import FirmowidUI.Components.Link
  import FirmowidWeb.Delegations.Components.Delegation
  import FirmowidWeb.DesignSystem.Components.Badge
  import Phoenix.Component, except: [link: 1]

  attr :delegations, :list, required: true

  @doc """
  Renders the trips as a table with fixed columns, so dates and statuses line up.
  On a phone each trip is a block: the title on its own line, the rest below it.
  """
  @spec delegations_list(map()) :: Phoenix.LiveView.Rendered.t()
  def delegations_list(assigns) do
    ~H"""
    <table :if={@delegations != []} class="w-full table-fixed text-start max-md:block">
      <col />
      <col class="w-36" />
      <col class="w-44" />
      <col class="w-24" />
      <thead class="max-md:hidden">
        <tr class="border-be border-grey-100">
          <th scope="col" class={header_styles()}>
            {pgettext("business trips table", "Business trip")}
          </th>
          <th scope="col" class={header_styles()}>
            {pgettext("business trips table", "Dates")}
          </th>
          <th scope="col" class={header_styles()}>{gettext("Status")}</th>
          <th scope="col"><span class="sr-only">{gettext("Actions")}</span></th>
        </tr>
      </thead>
      <tbody class="divide-y divide-grey-100 max-md:block">
        <tr
          :for={delegation <- @delegations}
          class="max-md:flex max-md:flex-wrap max-md:items-center max-md:gap-x-3 max-md:gap-y-2 max-md:py-3"
        >
          <td class="py-3 pe-4 max-md:basis-full max-md:p-0">
            <.delegation_title
              delegation={delegation}
              is_link={
                delegation.status in [:in_progress, :awaiting_signature, :submitted, :complete]
              }
            />
          </td>
          <td class="py-3 pe-4 text-sm tabular-nums max-md:p-0">
            <.date_range start_date={delegation.start_date} end_date={delegation.end_date} />
          </td>
          <td class="py-3 pe-4 max-md:p-0">
            <.status_badge status={delegation.status} />
          </td>
          <td class="py-3 text-end max-md:ms-auto max-md:p-0">
            <.link
              :if={delegation.order_editable?}
              kind="button"
              variant="outline"
              size="small"
              navigate={FirmowidWeb.Delegations.Utilities.Navigation.edit_path(delegation.reference)}
            >
              {gettext("Edit")}
            </.link>
          </td>
        </tr>
      </tbody>
    </table>
    <p :if={@delegations == []} class="text-sm text-grey-500">{gettext("No business trips.")}</p>
    """
  end

  # The same header style as the list of invoices.
  defp header_styles, do: "pbe-3 pe-4 text-start text-xs font-normal text-grey-700 uppercase"

  attr :delegation, :map, required: true
  attr :is_link, :boolean, required: true

  defp delegation_title(assigns) do
    ~H"""
    <div class="flex min-w-0 items-center gap-2">
      <.link
        :if={@is_link}
        kind="unstyled"
        navigate={FirmowidWeb.Delegations.Utilities.Navigation.show_path(@delegation.reference)}
        class="truncate hover:underline"
      >
        {@delegation.title}
      </.link>
      <p :if={!@is_link} class="truncate">{@delegation.title}</p>
      <.badge :if={@delegation.status == :in_progress}>{gettext("Draft version")}</.badge>
    </div>
    """
  end
end
