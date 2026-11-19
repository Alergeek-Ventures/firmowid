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

  attr :placement, :string,
    values: ~w(top top-start top-end bottom left right),
    default: "top"

  attr :title, :string, default: nil, doc: "a bold first line above the text"

  attr :variant, :string,
    values: ~w(default hint),
    default: "default",
    doc: "`hint` is the light Figma \"Information tooltip\" with an arrow"

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
      data-tippy-theme={@variant == "hint" && "hint"}
      data-tippy-arrow={@variant == "hint" && "true"}
      data-tippy-maxWidth={@variant == "hint" && "220"}
      data-tippy-hideOnClick={@variant == "hint" && "false"}
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
