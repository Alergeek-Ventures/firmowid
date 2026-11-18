defmodule FirmowidWeb.Assistant.Components.Controls do
  @moduledoc "Assistant panel and page controls and draft composer; events belong to the assistant LiveView."
  use FirmowidWeb, :html

  alias FirmowidUI.Components.Button
  alias FirmowidUI.Components.Inputs
  alias FirmowidUI.Components.Link
  alias FirmowidUI.Utilities.ButtonStyles
  alias FirmowidWeb.Assistant.Utilities.Presentation
  alias Phoenix.LiveView.Rendered

  attr :history_open?, :boolean, required: true
  attr :title, :string, default: nil, doc: "The conversation's subject, once it has one."
  attr :page_path, :string, default: nil, doc: "The full assistant page, when available."

  @doc "Renders the panel's bar: history, the conversation subject, a new conversation, full screen and close."
  @spec header(map()) :: Rendered.t()
  def header(assigns) do
    assigns = assign(assigns, :ghost_classes, ButtonStyles.variant_classes("ghost", nil))

    ~H"""
    <header class="flex flex-none items-center gap-0.5 border-be border-grey-200 ps-2 pe-1.5 min-block-12">
      <.history_toggle history_open?={@history_open?} />
      <span class="flex-1 truncate px-1.5 font-medium text-grey-900">{@title}</span>
      <.new_conversation />
      <Link.link
        :if={@page_path}
        id="assistant-expand"
        kind="unstyled"
        navigate={@page_path}
        aria-label={gettext("Open the assistant in full screen")}
        title={gettext("Open the assistant in full screen")}
        class={[
          "inline-flex size-8 shrink-0 items-center justify-center rounded-md border transition duration-100 ease-out min-block-9 min-inline-9 pointer-coarse:min-block-11 pointer-coarse:min-inline-11 [&>svg]:size-4",
          @ghost_classes
        ]}
      ><Lucideicons.maximize_2 aria-hidden="true" /></Link.link>
      <.icon_button
        label={gettext("Close assistant")}
        class="min-block-9 min-inline-9 pointer-coarse:min-block-11 pointer-coarse:min-inline-11"
        phx-click="close"
      ><Lucideicons.x aria-hidden="true" /></.icon_button>
    </header>
    """
  end

  attr :history_open?, :boolean, required: true

  attr :conversation?, :boolean,
    required: true,
    doc: "Whether a conversation is open, not the start screen."

  attr :title, :string, default: nil

  @doc """
  Renders the page's bar. The start screen has only the history; a conversation adds its subject
  and a new conversation, labelled on a wide screen.
  """
  @spec page_header(map()) :: Rendered.t()
  def page_header(assigns) do
    ~H"""
    <header
      :if={!@conversation?}
      class="flex flex-none items-center px-2 block-16 motion-safe:animate-fade-in @min-[40rem]/assistant:px-6"
    >
      <Button.button
        id="assistant-history-toggle"
        type="button"
        variant="ghost"
        size="small"
        class="pointer-coarse:min-block-11"
        phx-click="history"
        aria-expanded={to_string(@history_open?)}
        aria-controls="assistant-history"
      >
        <Lucideicons.history aria-hidden="true" />{gettext("History")}
      </Button.button>
    </header>
    <%!-- A phone gets 44 px targets with icons only; the title takes the rest of the row. --%>
    <header
      :if={@conversation?}
      class="flex flex-none items-center gap-1 border-be border-grey-200 p-1 motion-safe:animate-fade-in @min-[40rem]/assistant:gap-2 @min-[40rem]/assistant:px-6 @min-[40rem]/assistant:py-0 @min-[40rem]/assistant:block-16"
    >
      <.icon_button
        id="assistant-history-toggle"
        label={gettext("Conversation history")}
        size="big"
        class="min-block-11 min-inline-11 @min-[40rem]/assistant:min-block-9 @min-[40rem]/assistant:min-inline-9 [&>svg]:size-5!"
        phx-click="history"
        aria-expanded={to_string(@history_open?)}
        aria-controls="assistant-history"
      ><Lucideicons.history aria-hidden="true" /></.icon_button>
      <h2 class="flex-1 truncate text-sm/[normal] font-medium text-grey-900">{@title}</h2>
      <Button.button
        id="assistant-new-conversation"
        type="button"
        variant="ghost"
        size="small"
        class="@max-[40rem]/assistant:hidden"
        phx-click={JS.dispatch("assistant-restart", to: "#firmowid-assistant")}
      >
        <Lucideicons.plus aria-hidden="true" />{gettext("New conversation")}
      </Button.button>
      <.icon_button
        label={gettext("New conversation")}
        size="big"
        class="min-block-11 min-inline-11 @min-[40rem]/assistant:hidden [&>svg]:size-5!"
        phx-click={JS.dispatch("assistant-restart", to: "#firmowid-assistant")}
      ><Lucideicons.plus aria-hidden="true" /></.icon_button>
    </header>
    """
  end

  @doc "Renders the page drawer's heading with its close button."
  @spec page_history_header(map()) :: Rendered.t()
  def page_history_header(assigns) do
    ~H"""
    <header class="flex flex-none items-center justify-between gap-2 ps-4 pe-2 min-block-13">
      <h1 class="text-base/tight font-medium">{gettext("Conversations")}</h1>
      <.icon_button
        label={gettext("Back to the conversation")}
        class="min-block-9 min-inline-9 pointer-coarse:min-block-11 pointer-coarse:min-inline-11"
        phx-click="history"
      ><Lucideicons.x aria-hidden="true" /></.icon_button>
    </header>
    """
  end

  attr :history_open?, :boolean, required: true

  defp history_toggle(assigns) do
    ~H"""
    <.icon_button
      id="assistant-history-toggle"
      label={gettext("Conversation history")}
      class="min-block-9 min-inline-9 aria-expanded:not-active:bg-grey-200 pointer-coarse:min-block-11 pointer-coarse:min-inline-11"
      phx-click="history"
      aria-expanded={to_string(@history_open?)}
      aria-controls="assistant-history"
    ><Lucideicons.history aria-hidden="true" /></.icon_button>
    """
  end

  defp new_conversation(assigns) do
    ~H"""
    <.icon_button
      id="assistant-new-conversation"
      label={gettext("New conversation")}
      class="min-block-9 min-inline-9 pointer-coarse:min-block-11 pointer-coarse:min-inline-11"
      phx-click={JS.dispatch("assistant-restart", to: "#firmowid-assistant")}
    ><Lucideicons.plus aria-hidden="true" /></.icon_button>
    """
  end

  attr :conversation_id, :string, required: true
  attr :status, :atom, required: true
  attr :form_error, :string, default: nil
  attr :history_open?, :boolean, required: true

  attr :start?, :boolean,
    default: false,
    doc: "Whether the field sits on the page's start screen."

  @doc "Keeps the hook-owned input mounted while switching conversations and history."
  @spec composer(map()) :: Rendered.t()
  def composer(assigns) do
    ~H"""
    <Button.button
      id="assistant-new-messages"
      type="button"
      variant="unstyled"
      class="-mbs-1 mbe-2 flex cursor-pointer items-center justify-center gap-1.5 self-center rounded-full border border-grey-200 bg-white px-3 py-[.4rem] text-xs/tight font-normal select-none block-8 hover:bg-grey-100 active:bg-grey-300"
      hidden
    >
      <Lucideicons.arrow_down class="size-4" aria-hidden="true" />{gettext("New messages")}
    </Button.button>

    <%!--
      On the start screen the field sits under the greeting; in a conversation it stays at the
      bottom, on a phone above a divider. The placeholder follows the hook (`data-placeholder*`):
      the input ignores server updates.
    --%>
    <form
      id="assistant-form"
      phx-submit="send"
      class={[
        "mx-auto flex-none inline-full",
        if(@start?,
          do: "px-4 max-inline-3xl @min-[40rem]/assistant:px-6",
          else:
            "border-bs border-grey-200 px-3 pbs-2 pbe-[max(.75rem,env(safe-area-inset-bottom))] @min-[40rem]/assistant:border-0 @min-[40rem]/assistant:px-6 @min-[40rem]/assistant:pbs-0 @min-[40rem]/assistant:pbe-6 @min-[40rem]/assistant:max-inline-202"
        )
      ]}
      data-placeholder={
        if(@start?,
          do: gettext("For example: how much did we spend on subcontractors in October?"),
          else: gettext("Ask about invoices, transfers, costs or projects")
        )
      }
      data-placeholder-compact={gettext("Ask a question")}
      hidden={@history_open?}
    >
      <input type="hidden" name="conversation_id" value={@conversation_id} />
      <p :if={@form_error} class="mbs-1 mbe-2 text-sm/5 text-brick-700" role="alert">
        {@form_error}
      </p>
      <p :if={@status == :awaiting_approval} class="mbe-2 text-xs/5 text-grey-700">
        {gettext("Confirm or reject the plan before sending another message.")}
      </p>
      <div class="grid grid-cols-[minmax(0,1fr)_auto] items-end gap-1 rounded-sm border border-grey-200 bg-white py-1 ps-4 pe-1 focus-within:border-grey-700 motion-safe:transition-colors motion-safe:duration-150 @min-[40rem]/assistant:gap-2 @min-[40rem]/assistant:py-[7px] @min-[40rem]/assistant:ps-[15px] @min-[40rem]/assistant:pe-[7px]">
        <%!-- Six lines at most, then it scrolls inside. --%>
        <Inputs.input
          type="textarea"
          id="assistant-input"
          name="message"
          value=""
          rows="1"
          maxlength="20000"
          required
          placeholder={gettext("Ask a question")}
          aria-label={gettext("Message to the assistant")}
          phx-update="ignore"
          input_class="block field-sizing-content min-h-0! rounded-none! border-0! px-0! py-2.75! text-base/[1.35]! shadow-none! placeholder:text-grey-500! max-block-[calc(6lh+1.375rem)] focus:ring-0! @min-[40rem]/assistant:py-1! @min-[40rem]/assistant:text-base/7! @min-[40rem]/assistant:max-block-[calc(6lh+.5rem)]"
        />
        <%!--
          Disabled while the field is empty or the assistant is busy. The hook owns `disabled`:
          it follows the typed text, which the server does not see.
        --%>
        <Button.button
          id="assistant-send"
          type="submit"
          variant="unstyled"
          class="group/send relative inline-flex size-11 cursor-pointer items-center justify-center rounded-sm bg-grey-800 p-0 enabled:hover:bg-grey-900 enabled:active:scale-95 enabled:active:bg-black disabled:cursor-default motion-safe:transition-[background-color,scale] motion-safe:duration-150 @min-[40rem]/assistant:size-9"
          disabled
          data-busy={to_string(@status in [:running, :awaiting_approval])}
          phx-mounted={JS.ignore_attributes("disabled")}
          aria-label={gettext("Send message")}
        >
          <img
            src={~p"/images/assistant/send.svg"}
            alt=""
            class="absolute size-5 group-disabled/send:opacity-0 motion-safe:transition-opacity motion-safe:duration-200"
          />
          <img
            src={~p"/images/assistant/send-disabled.svg"}
            alt=""
            class="absolute size-5 opacity-0 group-disabled/send:opacity-100 motion-safe:transition-opacity motion-safe:duration-200"
          />
        </Button.button>
      </div>
    </form>
    """
  end

  attr :open, :boolean, required: true
  attr :status, :atom, required: true

  @doc "Renders the closed-panel launcher and announces the current conversation status."
  @spec launcher(map()) :: Rendered.t()
  def launcher(assigns) do
    ~H"""
    <Button.button
      id="assistant-launcher"
      type="button"
      variant="special"
      class="shadow-lg motion-safe:animate-fade-in max-md:hidden [body:has([data-assistant-entry])_&]:hidden"
      phx-click="open"
      hidden={@open}
      aria-expanded={to_string(@open)}
      aria-controls="assistant-panel"
    >
      <Lucideicons.messages_square class="size-5" aria-hidden="true" />
      <span>{launcher_label(@status)}</span>
      <span
        :if={@status == :awaiting_approval}
        class="size-2 rounded-full bg-grey-300"
        aria-hidden="true"
      ></span>
    </Button.button>
    <span class="sr-only" role="status">{Presentation.status_label(@status)}</span>
    """
  end

  defp launcher_label(:running), do: gettext("Assistant is working…")
  defp launcher_label(:awaiting_approval), do: gettext("Review changes")
  defp launcher_label(_status), do: gettext("Assistant")
end
