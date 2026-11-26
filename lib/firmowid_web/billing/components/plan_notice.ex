defmodule FirmowidWeb.Billing.Components.PlanNotice do
  @moduledoc """
  Tells a person that a feature belongs to a higher billing plan, in the place
  where the feature would be: a notice instead of a page or a form, a locked
  button instead of the button that starts it.
  """

  use FirmowidWeb, :html

  import FirmowidUI.Components.Button
  import FirmowidUI.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Billing.PlanCatalog
  alias FirmowidWeb.Billing.Utilities.Worksheet
  alias FirmowidWeb.Settings.Utilities.Navigation, as: SettingsNavigation
  alias Phoenix.LiveView.Rendered

  @doc """
  Renders the notice for a feature the organization's plan does not include. The
  owner, who manages the subscription, gets a link to it; everyone else is sent
  to the owner.
  """
  @spec plan_notice(map()) :: Rendered.t()
  attr :feature, :atom, required: true
  attr :current_org, :map, required: true
  attr :current_user, :map, required: true
  attr :size, :string, values: ~w(big small), default: "big"
  attr :class, :any, default: nil
  attr :rest, :global

  def plan_notice(assigns) do
    assigns =
      assigns
      |> assign(:title, title(assigns.feature))
      |> assign(:owner?, SettingsNavigation.visible?(:subscription, assigns))

    ~H"""
    <.empty_state title={@title} size={@size} class={@class} {@rest}>
      <:icon><Lucideicons.lock /></:icon>
      <span :if={not @owner?}>{gettext("Ask the company owner to change the plan.")}</span>
      <:action :if={@owner?}>
        <.link
          kind="button"
          variant="tertiary"
          navigate={SettingsNavigation.canonical_path(:subscription)}
        >
          {gettext("See the subscription")}
        </.link>
      </:action>
    </.empty_state>
    """
  end

  @doc """
  Renders the button that starts a feature the organization's plan does not
  include: disabled, with a lock in its corner and the reason in a tooltip. The
  inner block is the button's usual icon and label.
  """
  @spec plan_locked_button(map()) :: Rendered.t()
  attr :id, :string, required: true
  attr :feature, :atom, required: true
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def plan_locked_button(assigns) do
    assigns = assign(assigns, :title, title(assigns.feature))

    ~H"""
    <.tooltip id={@id} text={@title} class="relative">
      <.button type="button" variant="tertiary" size="small" class={@class} disabled>
        {render_slot(@inner_block)}
        <span class="sr-only">{@title}</span>
      </.button>
      <span
        aria-hidden="true"
        class="absolute -top-2 -right-2 flex size-5 items-center justify-center rounded-full bg-grey-900 text-white"
      >
        <Lucideicons.lock class="size-3" />
      </span>
    </.tooltip>
    """
  end

  defp title(feature), do: title(feature, feature |> PlanCatalog.plan_with() |> Worksheet.plan_label())

  defp title(:assistant, plan), do: gettext("The assistant is available in the %{plan} plan.", plan: plan)

  defp title(:leave_requests, plan), do: gettext("Absence requests are available in the %{plan} plan.", plan: plan)

  defp title(:employee_contracts, plan),
    do: gettext("Adding employee contracts is available in the %{plan} plan.", plan: plan)

  defp title(:delegations, plan), do: gettext("Business trips are available in the %{plan} plan.", plan: plan)
end
