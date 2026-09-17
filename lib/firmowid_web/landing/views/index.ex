defmodule FirmowidWeb.Landing.Views.Index do
  @moduledoc """
  Landing page for Firmowid marketing site.
  """

  use FirmowidWeb, :live_view

  import FirmowidWeb.Landing.Components.Hero
  import FirmowidWeb.Landing.Components.Primitives
  import FirmowidWeb.Landing.Components.Sections

  alias FirmowidWeb.Infrastructure.UserAuth

  @impl true
  def mount(_params, _session, socket) do
    # Redirect authenticated users with organization to role-based landing.
    if socket.assigns[:current_user] && socket.assigns.current_user.organization_id do
      {:ok, push_navigate(socket, to: UserAuth.signed_in_path_for_user(socket.assigns.current_user))}
    else
      {:ok,
       socket
       |> assign(page_title: gettext("Firmowid"))
       |> assign(
         meta_description:
           gettext(
             "Firmowid is KSeF-compliant invoicing, bank synchronization, working-time tracking, and team payroll for Polish companies."
           )
       )
       |> assign(public_marketing?: true)
       |> assign(billing_period: "monthly")
       |> assign(open_faq: nil), layout: false}
    end
  end

  @impl true
  def handle_event("set_billing_period", %{"period" => period}, socket) when period in ["monthly", "yearly"] do
    {:noreply, assign(socket, :billing_period, period)}
  end

  def handle_event("toggle_faq", %{"id" => id}, socket) do
    next_open = if socket.assigns.open_faq == id, do: nil, else: id
    {:noreply, assign(socket, :open_faq, next_open)}
  end

  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div id="top" data-landing-page="true" class="min-h-screen bg-[#f5f5f5] text-[#0f0f0f]">
      <.landing_navbar />

      <main>
        <.hero_section />
        <.top_metrics_section />
        <.audience_section />
        <.capabilities_section />
        <.proof_and_how_it_works_section />
        <.pricing_section billing_period={@billing_period} />
        <.team_section />
        <.faq_section open_faq={@open_faq} />
      </main>

      <.cta_footer />
    </div>
    """
  end
end
