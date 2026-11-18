defmodule FirmowidWeb.Assistant.Components.Start do
  @moduledoc """
  The assistant page's start screen around the question field: the greeting above it, the
  suggested questions and the latest conversations below it.
  """
  use FirmowidWeb, :html

  alias FirmowidUI.Components.Button
  alias FirmowidWeb.Assistant.Utilities.Presentation
  alias Phoenix.LiveView.Rendered

  @recent 3

  attr :name, :string, default: nil, doc: "The member's full name, greeted by the first one."

  @doc "Renders the greeting and what the assistant answers from."
  @spec intro(map()) :: Rendered.t()
  def intro(assigns) do
    assigns =
      assign(assigns, :first_name, assigns.name && assigns.name |> String.split() |> List.first())

    ~H"""
    <div class="mx-auto flex flex-none flex-col gap-2 px-4 pbs-8 pbe-8 inline-full max-inline-3xl motion-safe:animate-step-in @min-[40rem]/assistant:px-6 @min-[40rem]/assistant:pbs-18">
      <h2 class="text-[1.6875rem]/[normal] font-medium text-grey-900">
        {if @first_name,
          do: gettext("Good morning, %{name}", name: @first_name),
          else: gettext("Good morning")}
      </h2>
      <p class="text-base/normal text-grey-700">
        {gettext(
          "Ask about invoices, transfers, the team or projects. I answer from your company's data and show where I got it from."
        )}
      </p>
    </div>
    """
  end

  attr :conversation_id, :string, required: true
  attr :history, :list, required: true, doc: "Conversations, the open one included."

  @doc "Renders the suggested questions and the conversations to return to."
  @spec suggestions(map()) :: Rendered.t()
  def suggestions(assigns) do
    assigns =
      assign(
        assigns,
        :recent,
        assigns.history |> Enum.sort_by(& &1.updated_at, {:desc, DateTime}) |> Enum.take(@recent)
      )

    ~H"""
    <div class="mx-auto flex flex-none flex-col gap-8 px-4 pbs-8 pbe-16 inline-full max-inline-3xl @min-[40rem]/assistant:px-6">
      <div class="grid grid-cols-1 gap-2 @min-[40rem]/assistant:grid-cols-2">
        <%!-- The cards follow each other in, 40 ms apart. --%>
        <Button.button
          :for={{tile, index} <- Enum.with_index(Presentation.tiles())}
          type="button"
          variant="unstyled"
          phx-click="suggestion"
          phx-value-key={tile.key}
          phx-value-conversation-id={@conversation_id}
          class="flex cursor-pointer items-stretch gap-3 rounded-sm border border-grey-200 bg-white px-4 py-3 text-start select-none min-inline-0 active:scale-[.99] active:bg-grey-100 motion-safe:animate-step-in motion-safe:transition-[background-color,border-color,scale] motion-safe:duration-150 pointer-fine:hover:border-grey-400 phx-click-loading:opacity-75"
          style={"animation-delay: #{80 + index * 40}ms"}
        >
          <.page_tile key={tile.key} />
          <span class="flex flex-1 flex-col gap-1 text-sm min-inline-0">
            <span class="leading-[normal] font-medium text-grey-900">{tile.title}</span>
            <span class="leading-[1.35] text-grey-600">{tile.context}</span>
          </span>
        </Button.button>
      </div>

      <section
        :if={@recent != []}
        class="flex flex-col gap-2 border-bs border-grey-200 pbs-5 motion-safe:animate-step-in motion-safe:[animation-delay:240ms]"
        aria-labelledby="assistant-recent-heading"
      >
        <h3 id="assistant-recent-heading" class="text-sm/[normal] font-medium text-grey-900">
          {gettext("Back to a conversation")}
        </h3>
        <div class="flex flex-col">
          <Button.button
            :for={conversation <- @recent}
            id={"assistant-recent-#{conversation.id}"}
            type="button"
            variant="unstyled"
            class="group flex cursor-pointer items-center justify-between gap-4 text-start select-none min-block-9 pointer-coarse:min-block-11 phx-click-loading:opacity-75"
            phx-click="select_conversation"
            phx-value-id={conversation.id}
          >
            <span class="truncate text-sm/[1.35] text-grey-800 decoration-transparent underline-offset-[.2em] group-active:text-grey-900 motion-safe:transition-[color,text-decoration-color] motion-safe:duration-150 pointer-fine:group-hover:text-grey-900 pointer-fine:group-hover:underline pointer-fine:group-hover:decoration-current">
              {conversation.title || gettext("New conversation")}
            </span>
            <span class="flex-none text-xs/[normal] text-grey-600">{when_used(conversation.updated_at)}</span>
          </Button.button>
        </div>
      </section>
    </div>
    """
  end

  attr :key, :string, required: true

  # The ledger page a suggestion belongs to: teal sales, rust costs, grey everything else.
  defp page_tile(assigns) do
    ~H"""
    <span
      class={[
        "flex flex-none items-center justify-center rounded-[3px] inline-9",
        @key == "overdue" && "bg-teal-200",
        @key in ["accountant", "fixed_costs"] && "bg-rust-200 text-rust-900",
        @key == "projects" && "bg-grey-200 text-grey-800"
      ]}
      aria-hidden="true"
    >
      <img
        :if={@key == "overdue"}
        src={~p"/images/assistant/file-analytics.svg"}
        alt=""
        class="size-4"
      />
      <Lucideicons.arrow_left_right :if={@key in ["accountant", "fixed_costs"]} class="size-4" />
      <Lucideicons.folder_kanban :if={@key == "projects"} class="size-4" />
    </span>
    """
  end

  # Today with the time, yesterday by name, earlier days by date, all in Polish time.
  defp when_used(datetime) do
    local = DateTime.shift_zone!(datetime, "Europe/Warsaw")
    date = DateTime.to_date(local)
    today = Firmowid.LocalDate.today()

    cond do
      date == today -> gettext("today, %{time}", time: Calendar.strftime(local, "%H:%M"))
      date == Date.add(today, -1) -> gettext("yesterday")
      true -> Firmowid.Cldr.Date.to_string!(date, format: "d MMM")
    end
  end
end
