defmodule FirmowidWeb.Management.Components.DelegationsTab do
  @moduledoc "Delegation list presentation specific to employee management."

  use FirmowidWeb, :html

  import FirmowidWeb.Delegations.Components.Delegation, only: [date_range: 1]
  import FirmowidWeb.DesignSystem.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias FirmowidWeb.Delegations.Utilities.DelegationPresentation

  @doc "Renders an employee's delegations grouped by their management status."
  @spec delegations_tab(map()) :: Phoenix.LiveView.Rendered.t()
  attr :employee_id, :string, required: true
  attr :delegations, :list, required: true

  def delegations_tab(assigns) do
    assigns =
      assigns
      |> assign(
        :ongoing_delegations,
        Enum.filter(assigns.delegations, &(&1.status in [:pending, :in_progress]))
      )
      |> assign(
        :previous_delegations,
        Enum.filter(assigns.delegations, &(&1.status == :complete))
      )

    ~H"""
    <div class="space-y-8">
      <.delegations_section
        :if={@ongoing_delegations != []}
        title="Delegacje w toku"
        employee_id={@employee_id}
        delegations={@ongoing_delegations}
      />
      <.delegations_section
        :if={@previous_delegations != []}
        title="Poprzednie delegacje"
        employee_id={@employee_id}
        delegations={@previous_delegations}
      />
    </div>
    """
  end

  attr :title, :string, required: true
  attr :employee_id, :string, required: true
  attr :delegations, :list, required: true

  defp delegations_section(assigns) do
    ~H"""
    <section>
      <h2 class="text-grey-900 text-base/tight font-medium">{@title}</h2>
      <ul class="divide-grey-100 mt-4 divide-y">
        <li
          :for={delegation <- @delegations}
          class="flex items-center gap-3 py-3 first:pt-0 last:pb-0"
        >
          <p class="min-w-0 flex-1 truncate text-base">{delegation.title}</p>
          <p class="shrink-0 text-sm tabular-nums">
            <.date_range start_date={delegation.start_date} end_date={delegation.end_date} />
          </p>
          <.delegation_status delegation={delegation} employee_id={@employee_id} />
        </li>
      </ul>
    </section>
    """
  end

  attr :delegation, :map, required: true
  attr :employee_id, :string, required: true

  defp delegation_status(%{delegation: %{status: :pending}} = assigns) do
    ~H"""
    <.link
      kind="unstyled"
      navigate={~p"/zarzadzanie/pracownicy/#{@employee_id}/delegacje/#{@delegation.id}"}
      aria-label={"Otwórz delegację: #{@delegation.title}"}
      class="flex shrink-0 items-center gap-1"
    >
      <.status_badge status={@delegation.status} label="wymaga podpisu" />
      <Lucideicons.chevron_right class="text-grey-700 size-4" />
    </.link>
    """
  end

  defp delegation_status(assigns) do
    ~H"""
    <.status_badge
      status={@delegation.status}
      label={DelegationPresentation.status_label(@delegation.status)}
    />
    """
  end

  attr :status, :atom, required: true
  attr :label, :string, required: true

  defp status_badge(assigns) do
    assigns = assign(assigns, :styles, DelegationPresentation.status_badge_styles(assigns.status))

    ~H"""
    <span class={["shrink-0 rounded-full px-3 py-1 text-center text-sm", @styles]}>{@label}</span>
    """
  end
end
