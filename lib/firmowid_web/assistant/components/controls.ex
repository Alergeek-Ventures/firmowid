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
  attr :title, :string, default: nil

  @doc "Renders the page's slim bar: the history drawer, the conversation subject and a new conversation."
  @spec page_header(map()) :: Rendered.t()
  def page_header(assigns) do
    ~H"""
    <header class="flex flex-none items-center gap-1 px-3 min-block-13 max-md:px-1.5">
      <.history_toggle history_open?={@history_open?} />
      <h2 class="flex-1 truncate px-1.5 font-medium text-grey-900">{@title}</h2>
      <.new_conversation />
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

    <form
      id="assistant-form"
      phx-submit="send"
      class="mx-auto flex-none px-4 pbs-1 pbe-4 inline-full max-inline-182 max-md:pbe-[max(.75rem,env(safe-area-inset-bottom))] @min-[40rem]/assistant:px-6"
      hidden={@history_open?}
    >
      <input type="hidden" name="conversation_id" value={@conversation_id} />
      <p :if={@form_error} class="mbs-1 mbe-2 text-sm/5 text-brick-700" role="alert">
        {@form_error}
      </p>
      <p :if={@status == :awaiting_approval} class="mbe-2 text-xs/5 text-grey-700">
        {gettext("Confirm or reject the plan before sending another message.")}
      </p>
      <div class="grid grid-cols-[minmax(0,1fr)_auto] items-end gap-2 rounded-lg border border-grey-200 bg-white py-1.5 ps-1 pe-1.5 focus-within:border-grey-700">
        <Inputs.input
          type="textarea"
          id="assistant-input"
          name="message"
          value=""
          rows="1"
          maxlength="20000"
          required
          placeholder={gettext("Ask a question…")}
          aria-label={gettext("Message to the assistant")}
          phx-update="ignore"
          input_class="block field-sizing-content border-0! py-1.5! text-base shadow-none! max-block-40 focus:ring-0! md:text-sm"
        />
        <Button.button
          type="submit"
          variant="tertiary"
          class="size-8 justify-center p-0 min-block-8 min-inline-8 pointer-coarse:min-block-11 pointer-coarse:min-inline-11"
          disabled={@status in [:running, :awaiting_approval]}
          aria-label={gettext("Send message")}
        >
          <Lucideicons.arrow_up class="size-4" aria-hidden="true" />
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
      class="shadow-lg max-md:hidden [body:has([data-assistant-entry])_&]:hidden"
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
