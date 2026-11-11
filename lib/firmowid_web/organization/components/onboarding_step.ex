defmodule FirmowidWeb.Organization.Components.OnboardingStep do
  @moduledoc """
  The panel of one onboarding step. A new step enters with an animation and
  brings the page back to its top, so on a phone, where the button that leads
  to it sits far down, the new content is in view.
  """
  use FirmowidWeb, :html

  alias Phoenix.LiveView.Rendered

  @doc "Renders the step panel; give each step its own `id`, so a new step mounts anew."
  @spec onboarding_step(map()) :: Rendered.t()
  attr :id, :string, required: true
  slot :inner_block, required: true

  def onboarding_step(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook=".ScrollToTop"
      class="motion-safe:animate-step-in motion-reduce:animate-fade-in"
    >
      {render_slot(@inner_block)}
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".ScrollToTop">
      export default {
        mounted() {
          if (window.scrollY === 0) return;
          const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
          window.scrollTo({ top: 0, behavior: reduce ? "auto" : "smooth" });
        }
      }
    </script>
    """
  end
end
