defmodule FirmowidWeb.Landing.Components.LegalPage do
  @moduledoc """
  Shared layout for public legal pages.

  This component renders a common marketing-style page shell used by
  Terms of Service and Privacy Policy pages.
  """

  use FirmowidWeb, :html

  import FirmowidWeb.Landing.Components.Primitives, only: [cta_footer: 1, landing_navbar: 1]
  import Phoenix.Component, except: [link: 1]

  @doc """
  Renders legal-page shell with the shared navbar and footer.

  The function accepts arbitrary legal content via `:inner_block`.
  """
  @spec legal_page(map()) :: Phoenix.LiveView.Rendered.t()
  slot :inner_block, required: true
  attr :class, :string, default: "prose prose-neutral mx-auto max-w-3xl px-6 pt-32 pb-20 lg:px-10"

  def legal_page(assigns) do
    ~H"""
    <div
      id="top"
      class="flex min-h-screen flex-col bg-grey-100 text-[#0f0f0f] [--landing-accent:#8b3f13] [--landing-beige:#f0eae6] [--landing-line:#e6d7ce] [--landing-nav-height:64px] [background:var(--color-grey-100)] motion-reduce:**:animate-none! motion-reduce:**:transition-none! lg:[--landing-nav-height:96px] motion-reduce:[&_*::after]:animate-none! motion-reduce:[&_*::after]:transition-none! motion-reduce:[&_*::before]:animate-none! motion-reduce:[&_*::before]:transition-none! [&_a:focus-visible]:[outline:2px_solid_var(--color-orange-600)] [&_a:focus-visible]:outline-offset-4 [&_button:focus-visible]:[outline:2px_solid_var(--color-orange-600)] [&_button:focus-visible]:outline-offset-4 **:[[id]]:scroll-mt-[calc(var(--landing-nav-height)+24px)]"
    >
      <.landing_navbar />

      <article class={@class}>
        {render_slot(@inner_block)}
      </article>

      <.cta_footer />
    </div>
    """
  end
end
