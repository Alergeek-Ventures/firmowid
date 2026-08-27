defmodule FirmowidWeb.Timetracker.Components.Delegation do
  @moduledoc "Reusable presentation components for business trip delegations."

  use FirmowidWeb, :html

  import FirmowidWeb.DesignSystem.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias FirmowidWeb.Timetracker.Utilities.DelegationPresentation
  alias Phoenix.LiveView.Rendered

  @doc "Renders a consistently styled return link for delegation screens."
  @spec back_link(map()) :: Rendered.t()
  attr :navigate, :string, required: true
  attr :label, :string, default: "Wróć"
  attr :class, :any, default: nil

  def back_link(assigns) do
    ~H"""
    <.link kind="text" navigate={@navigate} size="small" class={["gap-2", @class]}>
      <span class="flex size-6 items-center justify-center rounded-full bg-black text-white">
        <Lucideicons.chevron_left aria-hidden="true" class="size-4" />
      </span>
      {@label}
    </.link>
    """
  end

  @doc "Renders a labeled form control row in the delegation form."
  @spec form_row(map()) :: Rendered.t()
  attr :label, :string, required: true
  attr :for, :string, required: true
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def form_row(assigns) do
    ~H"""
    <div class={["grid gap-x-5 gap-y-2 sm:grid-cols-[12rem_minmax(0,1fr)] sm:items-center", @class]}>
      <label for={@for} class="text-grey-700 text-base">{@label}</label>
      <div>{render_slot(@inner_block)}</div>
    </div>
    """
  end

  @doc "Renders a read-only delegation detail in a definition list."
  @spec detail_row(map()) :: Rendered.t()
  attr :label, :string, required: true
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def detail_row(assigns) do
    ~H"""
    <div class={["grid gap-1 sm:grid-cols-[12rem_minmax(0,1fr)] sm:gap-x-5", @class]}>
      <dt class="text-grey-700 text-base">{@label}</dt>
      <dd class="text-base text-black">{render_slot(@inner_block)}</dd>
    </div>
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
    <time datetime={Date.to_iso8601(@start_date)}>
      {DelegationPresentation.format_date(@start_date)}
    </time>
    <span aria-hidden="true"> - </span>
    <time datetime={Date.to_iso8601(@end_date)}>
      {DelegationPresentation.format_date(@end_date)}
    </time>
    """
  end
end
