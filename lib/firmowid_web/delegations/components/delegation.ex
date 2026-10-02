defmodule FirmowidWeb.Delegations.Components.Delegation do
  @moduledoc "Reusable presentation components for business trip delegations."

  use FirmowidWeb, :html

  alias FirmowidWeb.Delegations.Utilities.DelegationPresentation
  alias Phoenix.LiveView.Rendered

  @doc "Renders a labeled form control row in the delegation form."
  @spec form_row(map()) :: Rendered.t()
  attr :label, :string, required: true
  attr :for, :string, required: true
  attr :label_class, :any, default: nil
  slot :inner_block, required: true

  def form_row(assigns) do
    ~H"""
    <label for={@for} class={["text-grey-700 text-base", @label_class]}>{@label}</label>
    <div>{render_slot(@inner_block)}</div>
    """
  end

  @doc "Renders a read-only delegation detail in a definition list."
  @spec detail_row(map()) :: Rendered.t()
  attr :label, :string, required: true
  attr :dt_class, :any, default: nil, doc: "Additional classes for the definition term."
  attr :dd_class, :any, default: nil, doc: "Additional classes for the definition description."
  slot :inner_block, required: true

  def detail_row(assigns) do
    ~H"""
    <dt class={["text-grey-700 text-base", @dt_class]}>{@label}</dt>
    <dd class={["text-base text-black", @dd_class]}>{render_slot(@inner_block)}</dd>
    """
  end

  @doc "Renders the visual status of a delegation."
  @spec status_badge(map()) :: Rendered.t()
  attr :status, :atom, required: true
  attr :class, :any, default: nil

  def status_badge(assigns) do
    assigns =
      assign(assigns, :status_styles, DelegationPresentation.status_badge_styles(assigns.status))

    ~H"""
    <span class={[
      "shrink-0 rounded-full px-3 py-1 text-center text-sm",
      @status_styles,
      @class
    ]}>
      {DelegationPresentation.status_label(@status)}
    </span>
    """
  end

  @doc "Renders a delegation's dates using semantic time elements."
  @spec date_range(map()) :: Rendered.t()
  attr :start_date, Date, required: true
  attr :end_date, Date, required: true

  def date_range(assigns) do
    ~H"""
    <time datetime={"#{Date.to_iso8601(@start_date)}/#{Date.to_iso8601(@end_date)}"}>
      {DelegationPresentation.format_range(@start_date, @end_date)}
    </time>
    """
  end
end
