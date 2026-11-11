defmodule FirmowidWeb.DesignSystem.Components.Tooltip do
  @moduledoc """
  Tooltip on the shared Tippy hook with one delay and placement convention.
  """

  use FirmowidUI, :html

  @doc """
  Wraps content with a tooltip shown on hover and on keyboard focus. Do not put
  essential information only in a tooltip; it supplements a visible label.
  """
  @spec tooltip(map()) :: Phoenix.LiveView.Rendered.t()
  attr :id, :string, required: true
  attr :text, :string, required: true
  attr :placement, :string, values: ~w(top bottom left right), default: "top"

  attr :title, :string, default: nil, doc: "a bold first line above the text"

  attr :class, :any, default: nil
  slot :inner_block, required: true

  def tooltip(assigns) do
    assigns = assign(assigns, :content, content(assigns.title, assigns.text))

    ~H"""
    <span
      id={@id}
      phx-hook="Tippy"
      data-tippy-content={@content}
      data-tippy-allowHTML={@title && "true"}
      data-tippy-placement={@placement}
      data-tippy-delay="[300, 0]"
      class={["inline-flex", @class]}
    >
      {render_slot(@inner_block)}
    </span>
    """
  end

  defp content(nil, text), do: text

  # Tippy renders a titled tooltip as HTML, so both parts are escaped.
  defp content(title, text), do: "<strong>#{escape(title)}</strong><br>#{escape(text)}"

  defp escape(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end
