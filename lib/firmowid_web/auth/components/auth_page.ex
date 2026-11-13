defmodule FirmowidWeb.Auth.Components.AuthPage do
  @moduledoc """
  The shared frame of the sign-in and sign-up pages: a centred column over the
  figurine, and the Google button, so both pages look like one product.
  """
  use FirmowidWeb, :html

  import FirmowidUI.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias Phoenix.LiveView.Rendered

  @doc "Renders the page with its title above the content."
  @spec auth_page(map()) :: Rendered.t()
  attr :title, :string, required: true
  slot :inner_block, required: true

  def auth_page(assigns) do
    ~H"""
    <div class="relative flex h-screen w-screen items-center justify-center overflow-clip px-4">
      <img
        src="/images/figurine.png"
        alt=""
        class="pointer-events-none absolute -top-20 left-1/2 h-[135vh] opacity-10"
      />
      <div class="z-10 w-full max-w-xs">
        <h1 class="text-center text-2xl font-bold">{@title}</h1>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  @doc "Renders the button that signs in or up with Google."
  @spec google_button(map()) :: Rendered.t()
  attr :label, :string, required: true

  attr :remember_me, :boolean,
    default: false,
    doc: "the sign-in page's \"Remember me\" box (see `FirmowidWeb.Auth.Utilities.GoogleRememberMe`)"

  def google_button(assigns) do
    ~H"""
    <.link
      redirect={
        if @remember_me, do: ~p"/auth/user/google?remember_me=true", else: ~p"/auth/user/google"
      }
      kind="button"
      variant="outline"
      class="mt-8 w-full gap-3 bg-white text-sm font-medium shadow-sm"
    >
      <svg class="size-4" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
        <path
          d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"
          fill="#4285F4"
        />
        <path
          d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"
          fill="#34A853"
        />
        <path
          d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"
          fill="#FBBC05"
        />
        <path
          d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"
          fill="#EA4335"
        />
      </svg>
      {@label}
    </.link>
    """
  end
end
