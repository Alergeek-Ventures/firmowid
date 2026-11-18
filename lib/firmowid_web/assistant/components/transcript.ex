defmodule FirmowidWeb.Assistant.Components.Transcript do
  @moduledoc "Assistant transcript, suggestions and the sentence about the steps behind each answer."
  use FirmowidWeb, :html

  alias FirmowidUI.Components.Button
  alias FirmowidWeb.Assistant.Components.Invoice
  alias FirmowidWeb.Assistant.Components.Records
  alias FirmowidWeb.Assistant.Utilities.Presentation

  attr :start?, :boolean,
    default: false,
    doc: "The page's start screen shows its own suggestions."

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
      hidden={@history_open? or @start?}
    >
      <div
        id="assistant-content"
        class={[
          "mx-auto flex flex-col gap-6 px-4 pbs-5 pbe-6 inline-full @min-[40rem]/assistant:gap-8 @min-[40rem]/assistant:px-6 @min-[40rem]/assistant:pbs-8 @min-[40rem]/assistant:max-inline-202",
          @turns == [] && "flex-1"
        ]}
      >
        <.tiles :if={@turns == [] and !@subject and !@start?} conversation_id={@conversation_id} />
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
              class="flex cursor-pointer items-center justify-between gap-3 rounded-none py-3 text-start text-sm/[1.35] font-normal whitespace-normal text-grey-900 select-none inline-full min-block-11 active:opacity-80 pointer-fine:hover:underline phx-click-loading:opacity-75"
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
            class="self-end rounded-[1rem] border border-grey-200 bg-white px-3 py-2 text-base/normal wrap-anywhere whitespace-pre-wrap text-grey-900 max-inline-[85%] motion-safe:animate-step-in @min-[40rem]/assistant:max-inline-140"
            phx-no-format
          >{turn.text}</p>
          <%!--
            The avatar heads the answer. On a phone it shares its row with the steps and the
            answer takes the full width below; on a wide screen the answer is a column beside it.
          --%>
          <article
            :if={turn.role == :assistant}
            id={turn.id}
            class="grid grid-cols-[1.75rem_minmax(0,1fr)] items-start gap-x-2 text-grey-800 motion-safe:animate-step-in @min-[40rem]/assistant:gap-x-3"
          >
            <span class="col-start-1 row-start-1 flex size-7 items-center justify-center rounded-sm bg-black">
              <img src={~p"/images/assistant/assistant.svg"} alt="" class="size-4" />
            </span>
            <div class="col-span-2 col-start-1 row-start-1 flex flex-col gap-4 min-inline-0 @min-[40rem]/assistant:col-span-1 @min-[40rem]/assistant:col-start-2 @min-[40rem]/assistant:gap-3">
              <.steps :if={turn.steps} id={"#{turn.id}-steps"} steps={turn.steps} />
              <div :if={!turn.steps} class="min-block-7 @min-[40rem]/assistant:hidden"></div>
              <%= for block <- turn.blocks do %>
                <%= case block do %>
                  <% {:html, html} -> %>
                    <div class="prose text-base/normal wrap-anywhere text-grey-800 prose-neutral max-inline-none empty:hidden prose-headings:text-base prose-headings:font-medium prose-strong:font-semibold prose-strong:text-current prose-pre:overflow-auto prose-pre:max-block-48 prose-table:block prose-table:overflow-x-auto prose-table:text-sm prose-table:wrap-normal prose-th:text-xs">
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
            </div>
          </article>
        <% end %>

        <div
          :if={@status == :running}
          id="assistant-working"
          class="flex flex-col gap-2.5 motion-safe:animate-fade-in"
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

        <div
          :if={@error}
          class="flex gap-2.5 rounded-lg bg-brick-200 p-3 text-brick-700 motion-safe:animate-step-in"
          role="alert"
        >
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
        <span class="flex items-baseline justify-between gap-2 text-sm/[1.35] font-medium text-grey-900">
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

  # One sentence about what was looked at, beside the avatar; the chevron opens one line per
  # step. A phone shows the sentence alone.
  defp steps(assigns) do
    ~H"""
    <div class="flex flex-col gap-1 ps-9 text-xs/[normal] text-grey-600 min-inline-0 @min-[40rem]/assistant:-mbe-2 @min-[40rem]/assistant:ps-0">
      <details id={@id} class="group" phx-mounted={JS.ignore_attributes("open")}>
        <summary class="flex cursor-pointer list-none items-center gap-2 font-medium min-block-7 active:opacity-80 pointer-fine:hover:text-grey-900 [&::-webkit-details-marker]:hidden">
          <img
            :if={!@steps.failure}
            src={~p"/images/assistant/check.svg"}
            alt=""
            class="size-4 flex-none"
          />
          <Lucideicons.circle_alert
            :if={@steps.failure}
            class="size-4 flex-none text-brick-700"
            aria-hidden="true"
          />
          <span class="truncate">{@steps.summary}</span>
          <Lucideicons.chevron_down
            class="hidden size-4 flex-none group-open:rotate-180 motion-safe:transition-transform motion-safe:duration-200 motion-safe:ease-out @min-[40rem]/assistant:block"
            aria-hidden="true"
          />
        </summary>
        <ul class="mbs-1 grid gap-0.5 font-normal text-grey-700 motion-safe:animate-step-in">
          <li :for={line <- @steps.lines} id={"assistant-step-#{line.id}"}>
            {line.label}<span class="text-grey-600"> · {line.result}</span>
          </li>
        </ul>
      </details>
      <p :if={@steps.failure} class="text-brick-700">{@steps.failure}</p>
    </div>
    """
  end

  defp welcome_heading(%{type: type}) when type in ["employee", "project"], do: gettext("How can I help?")

  defp welcome_heading(%{type: "analysis"}), do: gettext("What would you like to know about these numbers?")

  defp welcome_heading(_subject), do: gettext("Choose a matching scenario")
end
