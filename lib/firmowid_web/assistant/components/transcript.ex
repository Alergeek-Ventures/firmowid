defmodule FirmowidWeb.Assistant.Components.Transcript do
  @moduledoc "Assistant transcript, suggestions and the sentence about the steps behind each answer."
  use FirmowidWeb, :html

  alias FirmowidUI.Components.Button
  alias FirmowidWeb.Assistant.Components.Invoice
  alias FirmowidWeb.Assistant.Components.Records
  alias FirmowidWeb.Assistant.Utilities.Presentation

  attr :turns, :list, required: true
  attr :subject, :map, required: true
  attr :conversation_id, :string, required: true
  attr :status, :atom, required: true
  attr :error, :string, default: nil
  attr :history_open?, :boolean, required: true
  attr :invoices, :map, required: true, doc: "Confirmations by preview tool call."
  attr :open_invoice, :string, default: nil
  attr :dismissed_invoices, :any, required: true
  slot :inner_block

  @doc "Keeps the scroll and streaming targets stable and renders sanitized transcript HTML."
  @spec transcript(map()) :: Phoenix.LiveView.Rendered.t()
  def transcript(assigns) do
    ~H"""
    <div
      id="assistant-messages"
      class="flex flex-1 scrollbar-gutter-stable flex-col overflow-y-auto overscroll-contain min-block-0"
      role="log"
      aria-live="off"
      aria-label={gettext("Conversation")}
      tabindex="0"
      hidden={@history_open?}
    >
      <div
        id="assistant-content"
        class={[
          "mx-auto flex flex-col gap-5 px-4 pbs-2 pbe-8 inline-full max-inline-182 @min-[40rem]/assistant:px-6",
          @turns == [] && "flex-1"
        ]}
      >
        <.tiles :if={@turns == [] and !@subject} conversation_id={@conversation_id} />
        <div :if={@turns == [] and @subject} class="flex flex-col gap-2 pbs-2">
          <h3 class="text-base/tight font-medium text-grey-900">{welcome_heading(@subject)}</h3>
          <div class="flex flex-col divide-y divide-grey-200">
            <Button.button
              :for={{key, label} <- Presentation.suggestions(@subject)}
              type="button"
              variant="unstyled"
              phx-click="suggestion"
              phx-value-key={key}
              phx-value-conversation-id={@conversation_id}
              class="flex cursor-pointer items-center justify-between gap-3 rounded-none py-3 text-start text-sm leading-[1.35] font-normal whitespace-normal text-grey-900 select-none inline-full min-block-11 active:opacity-80 pointer-fine:hover:underline phx-click-loading:opacity-75"
            >
              <span>{label}</span><Lucideicons.arrow_right
                class="size-4 flex-none text-grey-500"
                aria-hidden="true"
              />
            </Button.button>
          </div>
        </div>

        <%= for turn <- @turns do %>
          <p
            :if={turn.role == :user}
            id={turn.id}
            class="self-end rounded-lg bg-grey-100 px-3 py-2 wrap-anywhere whitespace-pre-wrap text-grey-900 max-inline-[min(80%,32.5rem)] max-sm:max-inline-[88%]"
            phx-no-format
          >{turn.text}</p>
          <article
            :if={turn.role == :assistant}
            id={turn.id}
            class="flex flex-col gap-2.5 text-grey-800 min-inline-0"
          >
            <%= for block <- turn.blocks do %>
              <%= case block do %>
                <% {:html, html} -> %>
                  <div class="prose prose-sm wrap-anywhere prose-neutral max-inline-[68ch] empty:hidden prose-headings:text-base prose-headings:font-medium prose-strong:font-medium prose-pre:overflow-auto prose-pre:max-block-48 prose-table:block prose-table:overflow-x-auto prose-table:wrap-normal prose-th:text-xs">
                    {html}
                  </div>
                <% {:records, records} -> %>
                  <Records.record_list records={records} />
                <% {:pick, pick} -> %>
                  <Records.pick_list
                    pick={pick}
                    conversation_id={@conversation_id}
                    active?={@status == :idle and turn == List.last(@turns)}
                  />
              <% end %>
            <% end %>
            <Invoice.card
              :for={id <- turn.invoices}
              :if={@invoices[id]}
              id={id}
              issuance={@invoices[id]}
              open?={@open_invoice == id}
              dismissed?={MapSet.member?(@dismissed_invoices, id)}
            />
            <.steps :if={turn.steps} id={"#{turn.id}-steps"} steps={turn.steps} />
          </article>
        <% end %>

        <div
          :if={@status == :running}
          id="assistant-working"
          class="flex flex-col gap-2.5"
          aria-busy="true"
        >
          <div class="flex items-center gap-2 text-sm/snug text-grey-600">
            <Lucideicons.loader_circle class="size-4 motion-safe:animate-spin" aria-hidden="true" />{gettext(
              "Working on your request"
            )}
          </div>
          <div
            id="assistant-live-text"
            phx-update="ignore"
            class="wrap-anywhere whitespace-pre-wrap text-grey-800"
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

  attr :conversation_id, :string, required: true

  # Fixed scenarios, vertically centred: two columns where there is room, one on a phone.
  defp tiles(assigns) do
    ~H"""
    <div class="my-auto grid grid-cols-[repeat(auto-fit,minmax(min(100%,16rem),1fr))] gap-3 py-4">
      <Button.button
        :for={tile <- Presentation.tiles()}
        type="button"
        variant="unstyled"
        phx-click="suggestion"
        phx-value-key={tile.key}
        phx-value-conversation-id={@conversation_id}
        class="group flex cursor-pointer flex-col items-stretch gap-1 rounded-md border border-grey-200 bg-white px-4 py-3.5 text-start font-normal whitespace-normal select-none min-inline-0 active:bg-grey-100 motion-safe:transition-colors motion-safe:duration-150 pointer-fine:hover:border-grey-400 pointer-fine:hover:bg-grey-50 phx-click-loading:opacity-75"
      >
        <span class="flex items-baseline justify-between gap-2 text-sm leading-[1.35] font-medium text-grey-900">
          <span>{tile.title}</span>
          <Lucideicons.arrow_right
            class="size-3.5 flex-none translate-y-0.5 text-grey-500 pointer-fine:group-hover:text-grey-900"
            aria-hidden="true"
          />
        </span>
        <span class="text-xs/snug text-grey-600">{tile.context}</span>
      </Button.button>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :steps, :map, required: true

  # One sentence about what was looked at; the chevron opens one line per step.
  defp steps(assigns) do
    ~H"""
    <div class="flex flex-col gap-1 text-[0.8125rem]/[1.45] text-grey-600">
      <p :if={@steps.failure} class="text-brick-700">{@steps.failure}</p>
      <details id={@id} class="group" phx-mounted={JS.ignore_attributes("open")}>
        <summary class="inline cursor-pointer list-none active:opacity-80 pointer-fine:hover:text-grey-900 [&::-webkit-details-marker]:hidden">
          {@steps.summary}<Lucideicons.chevron_down
            class="ms-1 inline-block size-3 -translate-y-px group-open:rotate-180 motion-safe:transition-transform motion-safe:duration-200 motion-safe:ease-out"
            aria-hidden="true"
          />
        </summary>
        <ul class="mbs-1 grid gap-0.5 text-grey-700">
          <li :for={line <- @steps.lines} id={"assistant-step-#{line.id}"}>
            {line.label}<span class="text-grey-600"> · {line.result}</span>
          </li>
        </ul>
      </details>
    </div>
    """
  end

  defp welcome_heading(%{type: type}) when type in ["employee", "project"], do: gettext("How can I help?")

  defp welcome_heading(_subject), do: gettext("Choose a matching scenario")
end
