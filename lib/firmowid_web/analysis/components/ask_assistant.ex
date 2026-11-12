defmodule FirmowidWeb.Analysis.Components.AskAssistant do
  @moduledoc """
  Starts an assistant conversation about the analysis view on screen: the assistant panel
  opens with the view's period, month or project and the figures it shows as context. It
  takes the place of the assistant's floating launcher, which a page with a
  `data-assistant-entry` element hides.
  """
  use FirmowidWeb, :html

  attr :id, :string, required: true

  attr :context, :map,
    required: true,
    doc: "`view` (summary, trends or projects), `from`, `to`, `month`, `project_id` and `title`"

  @doc "Renders the button asking the assistant about this view."
  @spec button(map()) :: Phoenix.LiveView.Rendered.t()
  def button(assigns) do
    ~H"""
    <FirmowidUI.Components.Button.button
      id={@id}
      type="button"
      variant="special"
      size="big"
      data-assistant-entry
      phx-click={JS.push("ask_analysis", target: "#firmowid-assistant", value: @context)}
    >
      <Lucideicons.messages_square aria-hidden="true" />
      {gettext("Ask the assistant")}
    </FirmowidUI.Components.Button.button>
    """
  end
end
