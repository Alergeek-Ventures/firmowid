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
    <div id="top" class="bg-grey-100 flex min-h-screen flex-col">
      <.landing_navbar />

      <article class={@class}>
        {render_slot(@inner_block)}
      </article>

      <.cta_footer />
    </div>
    """
  end
end
