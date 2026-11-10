defmodule FirmowidWeb.Organization.Components.OnboardingHeader do
  @moduledoc """
  Header of the onboarding pages, which hide the app navigation: the way back to
  the previous step (the wordmark on a step without one), the progress through
  the steps, and the way out, into the app for a member and logging out for
  anyone else.
  """
  use FirmowidWeb, :html

  import FirmowidUI.Components.Button
  import FirmowidUI.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias Phoenix.LiveView.Rendered

  @step_count 5

  @doc "Renders the header. `exit_path` leads a member into the app; without it the user can log out."
  @spec onboarding_header(map()) :: Rendered.t()
  attr :exit_path, :string, default: nil
  attr :back, :string, default: nil, doc: "the previous step; the wordmark stands in its place without it"

  attr :step, :any,
    default: nil,
    doc: "the step number, `:done` once every step is behind, or nil for no progress"

  def onboarding_header(assigns) do
    assigns = assign(assigns, :step_count, @step_count)

    ~H"""
    <%!-- Stays at the top while the step below it scrolls. --%>
    <header class="sticky top-0 z-20 grid grid-cols-[1fr_auto_1fr] items-center gap-3 bg-grey-100 py-6 lg:py-8">
      <%= if @back do %>
        <.link
          id="onboarding-back"
          kind="unstyled"
          patch={@back}
          class="group -ml-1 flex w-fit items-center gap-1.5 rounded-lg px-1 py-2 text-[0.9375rem] font-medium text-grey-700 transition-colors hover:text-black focus-visible:outline-2 focus-visible:outline-black"
        >
          <Lucideicons.arrow_left
            class="size-4 transition-transform group-hover:-translate-x-0.5"
            aria-hidden="true"
          />
          {gettext("Back")}
        </.link>
      <% else %>
        <span class="font-logo text-2xl font-bold tracking-tight text-grey-900">Firmowid</span>
      <% end %>

      <p :if={@step} class="flex items-center gap-1.5 text-sm text-grey-600 sm:gap-2">
        <span
          :for={number <- 1..@step_count}
          class={[
            "h-1 w-5 rounded-full sm:w-7",
            if(@step == :done or number <= @step, do: "bg-black", else: "bg-grey-200")
          ]}
        ></span>
        <span :if={@step != :done} class="ml-1 max-sm:sr-only">
          {gettext("Step %{number} of %{total}", number: @step, total: @step_count)}
        </span>
      </p>
      <span :if={is_nil(@step)}></span>

      <div class="justify-self-end">
        <%= if @exit_path do %>
          <.link
            kind="unstyled"
            navigate={@exit_path}
            class="text-sm text-grey-900 underline underline-offset-4"
          >
            {gettext("Go to Firmowid")}
          </.link>
        <% else %>
          <.form
            for={%{}}
            id="organization-logout-form"
            action={~p"/wyloguj"}
            method="delete"
            data-posthog-reset-on-submit="true"
          >
            <.button type="submit" variant="ghost" size="small" class="underline underline-offset-4">
              {pgettext("organization onboarding", "Log out")}
            </.button>
          </.form>
        <% end %>
      </div>
    </header>
    """
  end
end
