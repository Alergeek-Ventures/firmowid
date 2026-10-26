defmodule FirmowidWeb.Assistant.Components.History do
  @moduledoc "Scrollable conversation history with selection and pagination actions."
  use FirmowidWeb, :html

  alias FirmowidUI.Components.Button
  alias FirmowidWeb.Assistant.Utilities.Presentation

  attr :conversations, :list, required: true
  attr :conversation_id, :string, required: true
  attr :open, :boolean, required: true
  attr :more?, :boolean, required: true

  @doc "Renders history without owning its loading, selection or pagination state."
  @spec history(map()) :: Phoenix.LiveView.Rendered.t()
  def history(assigns) do
    ~H"""
    <section
      id="assistant-history"
      class="flex flex-1 scrollbar-gutter-stable flex-col gap-0.5 overflow-y-auto overscroll-contain p-2 min-block-0"
      aria-label={gettext("Conversation history")}
      hidden={!@open}
    >
      <p :if={@conversations == []} class="p-3 text-grey-700">
        {gettext("No conversations yet.")}
      </p>
      <Button.button
        :for={conversation <- @conversations}
        id={"assistant-history-#{conversation.id}"}
        type="button"
        variant="unstyled"
        class="group flex flex-none cursor-pointer flex-col items-stretch justify-center gap-0.5 rounded-lg border border-transparent px-3 py-2.5 text-start text-sm leading-[1.35] font-normal whitespace-normal select-none inline-full min-block-11 hover:bg-grey-100 active:bg-grey-200 aria-current:bg-grey-100 phx-click-loading:opacity-75"
        phx-click="select_conversation"
        phx-value-id={conversation.id}
        aria-current={if(conversation.id == @conversation_id, do: "true")}
      >
        <span class="line-clamp-2 overflow-clip wrap-anywhere group-aria-current:font-medium">
          {conversation.title || gettext("New conversation")}
        </span>
        <span class="flex flex-wrap gap-x-3 text-xs leading-[1.35] text-grey-600">
          <span>{Calendar.strftime(conversation.inserted_at, "%d.%m.%Y")}</span>
          <span :if={conversation.status != :idle} class="text-grey-700">
            {Presentation.status_label(conversation.status)}
          </span>
        </span>
      </Button.button>
      <Button.button
        :if={@more?}
        id="assistant-history-more"
        type="button"
        variant="outline"
        size="small"
        class="mx-3 my-2 self-start"
        phx-click="older_conversations"
      >{gettext("Show older conversations")}</Button.button>
    </section>
    """
  end
end
