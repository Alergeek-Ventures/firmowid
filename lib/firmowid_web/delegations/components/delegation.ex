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
    <label for={@for} class={["text-base text-grey-700", @label_class]}>{@label}</label>
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
    <dt class={["text-base text-grey-700", @dt_class]}>{@label}</dt>
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

  @doc "Renders the cost totals and balance of a settlement document."
  @spec settlement_summary(map()) :: Rendered.t()
  attr :document, :map, required: true
  slot :inner_block

  def settlement_summary(assigns) do
    ~H"""
    <section class="mt-6 rounded-lg bg-white p-5 shadow-sm">
      <h2 class="text-grey-500">Podsumowanie</h2>
      <dl class="mt-6 space-y-3 text-sm">
        <.summary_row label="Przejazdy" value={@document.transport_total} />
        <.summary_row label="Nocleg" value={@document.accommodation_total} />
        <.summary_row label="Inne" value={@document.other_total} />
        <.summary_row
          :if={@document.per_diem}
          label={gettext("Per diem")}
          value={@document.per_diem.per_diem}
        />
        <.summary_row
          :if={@document.per_diem && !Money.zero?(@document.per_diem.lump_sums)}
          label={gettext("Lump sums")}
          value={@document.per_diem.lump_sums}
        />
        <div class="my-5 space-y-3 border-y border-grey-100 py-5">
          <.summary_row label="Razem koszty" value={@document.total} strong />
          <.summary_row label="Pobrana zaliczka" value={@document.delegation.advance_amount} />
        </div>
        <.summary_row label={@document.balance_label} value={@document.balance} strong />
      </dl>
      {render_slot(@inner_block)}
    </section>
    """
  end

  attr :label, :string, required: true
  attr :value, Money, required: true
  attr :strong, :boolean, default: false

  defp summary_row(assigns) do
    ~H"""
    <div class={["flex justify-between gap-4", @strong && "font-medium"]}>
      <dt>{@label}</dt><dd class={[Money.zero?(@value) && "text-grey-500"]}>
        {DelegationPresentation.format_money(@value)}
      </dd>
    </div>
    """
  end
end
