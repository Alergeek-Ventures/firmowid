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

  attr :back, :any,
    default: nil,
    doc:
      "the previous step, a path patched to on the same page or `{:navigate, path}` on another; the wordmark stands in its place without it"

  attr :step, :any,
    default: nil,
    doc: "the step number, `:done` once every step is behind, or nil for no progress"

  attr :connecting_client, :string,
    default: nil,
    doc: "the AI client the person returns to after the last step, named beside the progress"

  def onboarding_header(assigns) do
    assigns = assign(assigns, :step_count, @step_count)

    ~H"""
    <%!-- Stays at the top while the step below it scrolls. --%>
    <header class="sticky top-0 z-20 grid grid-cols-[1fr_auto_1fr] items-center gap-3 bg-grey-100 py-6 lg:py-8">
      <%= if @back do %>
        <%!-- Turns in where the logo stood. On a phone only the arrow, as large as the way out. --%>
        <.link
          id="onboarding-back"
          kind="unstyled"
          {back_link(@back)}
          class="group -ml-1 flex w-fit items-center gap-1.5 rounded-lg px-1 py-2 text-[0.9375rem] font-medium text-grey-700 transition-colors hover:text-black focus-visible:outline-2 focus-visible:outline-black motion-safe:animate-swap-in max-sm:ml-0 max-sm:size-10.5 max-sm:justify-center max-sm:border max-sm:border-grey-300 max-sm:bg-white max-sm:p-0 max-sm:text-grey-900"
        >
          <Lucideicons.arrow_left
            class="size-4 transition-transform group-hover:-translate-x-0.5 max-sm:size-4.5"
            aria-hidden="true"
          />
          <span class="max-sm:sr-only">{gettext("Back")}</span>
        </.link>
      <% else %>
        <%!-- On a phone the wordmark gives way to the head, so the progress keeps its room. --%>
        <span class="font-logo text-2xl font-bold tracking-tight text-grey-900 max-sm:hidden">
          Firmowid
        </span>
        <img src={~p"/images/logo-head.svg"} alt="Firmowid" class="size-9 sm:hidden" />
      <% end %>

      <p
        :if={@step}
        class={[
          "flex items-center gap-1.5 text-sm text-grey-600 sm:gap-2",
          @connecting_client && "max-md:flex-col"
        ]}
      >
        <span class="flex items-center gap-1.5 sm:gap-2">
          <span
            :for={number <- 1..@step_count}
            class={[
              "h-1 w-5 rounded-full sm:w-7",
              if(@step == :done or number <= @step, do: "bg-black", else: "bg-grey-200")
            ]}
          ></span>
        </span>
        <%= cond do %>
          <% @step == :done -> %>
          <% @connecting_client -> %>
            <%!-- Narrower, where it ends goes on a line of its own under the bars. --%>
            <span class="ms-1 max-md:sr-only">
              {gettext("Step %{number} of %{total}, then back to %{client}",
                number: @step,
                total: @step_count,
                client: @connecting_client
              )}
            </span>
            <span class="text-xs md:hidden" aria-hidden="true">
              {gettext("At the end you return to %{client}", client: @connecting_client)}
            </span>
          <% true -> %>
            <span class="ms-1 max-sm:sr-only">
              {gettext("Step %{number} of %{total}", number: @step, total: @step_count)}
            </span>
        <% end %>
      </p>
      <span :if={is_nil(@step)}></span>

      <div class="justify-self-end">
        <%= if @exit_path do %>
          <.link
            kind="unstyled"
            navigate={@exit_path}
            class="text-sm text-grey-900 underline underline-offset-4 max-sm:inline-flex max-sm:h-10.5 max-sm:items-center max-sm:rounded-lg max-sm:border max-sm:border-grey-300 max-sm:bg-white max-sm:px-3 max-sm:font-medium max-sm:no-underline"
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
            <.tooltip
              id="organization-logout-tooltip"
              title={pgettext("organization onboarding", "Log out")}
              text={gettext("You will come back here after logging in again.")}
              placement="bottom"
            >
              <.button
                type="submit"
                variant="ghost"
                size="small"
                aria-label={pgettext("organization onboarding", "Log out")}
                class="max-sm:size-10.5 max-sm:rounded-lg max-sm:border-grey-300 max-sm:bg-white max-sm:text-grey-900"
              >
                <Lucideicons.log_out class="size-4.5" aria-hidden="true" />
              </.button>
            </.tooltip>
          </.form>
        <% end %>
      </div>
    </header>
    """
  end

  defp back_link({:navigate, path}), do: %{navigate: path}
  defp back_link(path), do: %{patch: path}
end
