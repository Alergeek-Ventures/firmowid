defmodule FirmowidWeb.Landing.Views.Index do
  @moduledoc """
  Public landing, pricing, features and FAQ pages.
  """

  use FirmowidWeb, :live_view

  import FirmowidWeb.Landing.Components.Faq
  import FirmowidWeb.Landing.Components.Hero
  import FirmowidWeb.Landing.Components.Pricing
  import FirmowidWeb.Landing.Components.Primitives
  import FirmowidWeb.Landing.Components.Sections

  alias Firmowid.Ash.Core
  alias FirmowidWeb.Infrastructure.UserAuth

  @impl true
  def mount(_params, session, socket) do
    if socket.assigns.live_action == :home && socket.assigns[:current_user] &&
         Core.load_member(socket.assigns.current_user).member do
      {:ok,
       push_navigate(socket,
         to:
           UserAuth.signed_in_path_for_user(
             socket.assigns.current_user,
             session[UserAuth.organization_session_key()]
           )
       )}
    else
      {:ok,
       socket
       |> assign(metadata(socket.assigns.live_action))
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
    <div
      id="top"
      data-landing-page="true"
      class="min-h-screen bg-grey-100 text-[#0f0f0f] [--landing-accent:#8b3f13] [--landing-beige:#f0eae6] [--landing-line:#e6d7ce] [--landing-nav-height:--spacing(16)] motion-reduce:**:animate-none! motion-reduce:**:transition-none! lg:[--landing-nav-height:--spacing(24)] motion-reduce:[&_*::after]:animate-none! motion-reduce:[&_*::after]:transition-none! motion-reduce:[&_*::before]:animate-none! motion-reduce:[&_*::before]:transition-none! [&_a:focus-visible]:outline-2 [&_a:focus-visible]:outline-offset-4 [&_a:focus-visible]:outline-orange-600 [&_button:focus-visible]:outline-2 [&_button:focus-visible]:outline-offset-4 [&_button:focus-visible]:outline-orange-600 **:[[id]]:scroll-mt-[calc(var(--landing-nav-height)+var(--spacing)*6)]"
    >
      <.landing_navbar />

      <main>
        <h1
          :if={@live_action != :home}
          class="mx-auto w-[calc(100%-var(--spacing)*8)] max-w-284.75 pt-18 text-3xl leading-[1.1] font-bold tracking-[-0.03em]"
        >
          {@page_title}
        </h1>
        <.hero_section :if={@live_action == :home} />
        <.top_metrics_section :if={@live_action == :home} />
        <.audience_section :if={@live_action == :home} />
        <.capabilities_section :if={@live_action in [:home, :features]} />
        <.assistants_section :if={@live_action in [:home, :features]} />
        <.proof_section :if={@live_action == :home} />
        <.how_it_works_section :if={@live_action == :home} />
        <.pricing_section :if={@live_action in [:home, :pricing]} billing_period={@billing_period} />
        <.open_source_section :if={@live_action == :home} />
        <.team_section :if={@live_action == :home} />
        <.faq_section :if={@live_action in [:home, :faq]} open_faq={@open_faq} />
      </main>

      <.cta_footer />
    </div>
    """
  end

  defp metadata(:home) do
    [
      page_title: gettext("Firmowid - free KSeF invoices, banking and team time tracking"),
      meta_description:
        gettext("Free KSeF invoicing, bank synchronization, time tracking, leave and business trips in one place.")
    ]
  end

  defp metadata(:pricing) do
    [
      page_title: gettext("Firmowid pricing — choose your plan"),
      meta_description:
        gettext("Compare the Free, Entrepreneur and Company plans. Monthly or annual billing, no hidden charges.")
    ]
  end

  defp metadata(:features) do
    [
      page_title: gettext("Firmowid features — KSeF, banking and your team"),
      meta_description: gettext("Invoices, transaction matching, time tracking, leave and business trips in one place.")
    ]
  end

  defp metadata(:faq) do
    [
      page_title: gettext("Firmowid — frequently asked questions"),
      meta_description: gettext("Answers about KSeF, bank integrations, data security, migration and Firmowid plans.")
    ]
  end
end
