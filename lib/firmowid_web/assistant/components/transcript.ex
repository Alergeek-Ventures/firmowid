defmodule FirmowidWeb.Assistant.Components.Transcript do
  @moduledoc "Assistant transcript, contextual suggestions and tool progress presentation."
  use FirmowidWeb, :html

  alias FirmowidUI.Components.Button
  alias FirmowidWeb.Assistant.Utilities.Presentation

  attr :turns, :list, required: true
  attr :subject, :map, required: true
  attr :conversation_id, :string, required: true
  attr :status, :atom, required: true
  attr :error, :string, default: nil
  attr :history_open?, :boolean, required: true
  slot :inner_block

  @doc "Keeps the scroll and streaming targets stable and renders sanitized transcript HTML."
  @spec transcript(map()) :: Phoenix.LiveView.Rendered.t()
  def transcript(assigns) do
    ~H"""
    <div
      id="assistant-messages"
      class="flex-1 scrollbar-gutter-stable overflow-y-auto overscroll-contain p-4 min-block-0"
      role="log"
      aria-live="off"
      aria-label={gettext("Conversation")}
      tabindex="0"
      hidden={@history_open?}
    >
      <div id="assistant-content" class="flex flex-col gap-4">
        <div :if={@turns == []} class="flex flex-col gap-2">
          <h3 class="text-base/tight font-medium">{welcome_heading(@subject)}</h3>
          <p :if={!@subject} class="text-sm/snug text-grey-700">
            {gettext("Find payments, check matches and prepare changes. You decide what gets saved.")}
          </p>
          <div class="mbs-1 flex flex-col gap-2">
            <Button.button
              :for={{key, label} <- Presentation.suggestions(@subject)}
              type="button"
              variant="unstyled"
              phx-click="suggestion"
              phx-value-key={key}
              phx-value-conversation-id={@conversation_id}
              class="flex cursor-pointer items-center justify-between gap-3 rounded-lg border border-transparent bg-grey-100 px-3 py-2.5 text-start text-sm leading-[1.35] font-normal whitespace-normal select-none inline-full min-block-11 hover:shadow-sm active:bg-grey-200 motion-safe:transition-shadow motion-safe:duration-150 motion-safe:ease-out phx-click-loading:opacity-75"
            >
              <span>{label}</span><Lucideicons.chevron_right
                class="size-4 flex-none text-grey-500"
                aria-hidden="true"
              />
            </Button.button>
          </div>
        </div>

        <article
          :for={turn <- @turns}
          id={turn.id}
          class={["min-inline-0", turn.role == :user && "self-end max-inline-[85%]"]}
        >
          <%= if turn.role == :user do %>
            <p
              class="rounded-lg bg-grey-100 px-3 py-2 wrap-anywhere whitespace-pre-wrap"
              phx-no-format
            >{turn.text}</p>
          <% else %>
            <details
              :if={turn.tools != []}
              id={"#{turn.id}-tools"}
              class="group mbe-2 text-xs/normal text-grey-600"
              phx-mounted={JS.ignore_attributes("open")}
            >
              <summary class="inline-flex cursor-pointer list-none items-center gap-1 rounded-sm min-block-7 hover:text-grey-900 active:opacity-80 [&::-webkit-details-marker]:hidden">
                <span>{ngettext("%{count} step", "%{count} steps", length(turn.tools))}</span><Lucideicons.chevron_down
                  class="size-4 group-open:rotate-180 motion-safe:transition-transform motion-safe:duration-150 motion-safe:ease-out"
                  aria-hidden="true"
                />
              </summary>
              <div class="mbs-1 border-s border-grey-200 ps-3">
                <.tool_step :for={tool <- turn.tools} tool={tool} />
              </div>
            </details>
            <div
              :if={turn.text != ""}
              class="prose prose-sm wrap-anywhere prose-neutral max-inline-none prose-headings:text-base prose-headings:font-medium prose-pre:overflow-auto prose-pre:max-block-48 prose-table:block prose-table:overflow-x-auto prose-table:wrap-normal prose-th:text-xs"
            >
              {turn.html}
            </div>
          <% end %>
        </article>

        <div
          :if={@status == :running}
          id="assistant-working"
          class="flex flex-col gap-2.5"
          aria-busy="true"
        >
          <div class="flex items-center gap-2 text-xs/snug text-grey-700">
            <Lucideicons.loader_circle class="size-4 motion-safe:animate-spin" aria-hidden="true" />{gettext(
              "Working on your request"
            )}
          </div>
          <div
            id="assistant-live-text"
            phx-update="ignore"
            class="wrap-anywhere whitespace-pre-wrap"
            aria-hidden="true"
            phx-no-format
          ></div>
        </div>

        {render_slot(@inner_block)}

        <div :if={@error} class="flex gap-2.5 rounded-lg bg-brick-200 p-3 text-brick-700" role="alert">
          <Lucideicons.circle_alert class="size-5 shrink-0" aria-hidden="true" />
          <div>
            <strong class="text-sm/5">{gettext("The response was interrupted")}</strong><p class="mbs-1 text-sm/5">
              {Presentation.failure_message(@error)}
            </p>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :tool, :map, required: true

  defp tool_step(assigns) do
    ~H"""
    <div id={"assistant-step-#{@tool.id}"}>
      <div class="flex items-center gap-2 min-block-7">
        <Lucideicons.circle_check
          :if={@tool.status == :done}
          class="size-4 text-moss-700"
          aria-hidden="true"
        />
        <Lucideicons.circle_alert
          :if={@tool.status in [:error, :unknown]}
          class="size-4 text-brick-700"
          aria-hidden="true"
        />
        <Lucideicons.circle_minus
          :if={@tool.status == :denied}
          class="size-4 text-grey-600"
          aria-hidden="true"
        />
        <Lucideicons.circle
          :if={@tool.status == :pending}
          class="size-4 text-grey-600"
          aria-hidden="true"
        />
        <span class="flex-1 min-inline-0">{@tool.label}</span>
        <span class="text-xs/snug text-grey-700">{tool_status_label(@tool.status, @tool.summary)}</span>
      </div>
    </div>
    """
  end

  defp welcome_heading(nil), do: gettext("Let's put your transactions in order")

  defp welcome_heading(%{type: type}) when type in ["employee", "project"], do: gettext("How can I help?")

  defp welcome_heading(_subject), do: gettext("Choose a matching scenario")

  defp tool_status_label(:done, nil), do: gettext("Completed")
  defp tool_status_label(:done, summary), do: summary
  defp tool_status_label(:pending, _summary), do: gettext("Waiting")
  defp tool_status_label(:denied, _summary), do: gettext("Not performed")
  defp tool_status_label(:unknown, _summary), do: gettext("Check the result")
  defp tool_status_label(:error, _summary), do: gettext("Error")
end
