defmodule FirmowidWeb.Invoicing.Components.MatchingComponents do
  @moduledoc "Shared presentation for invoice and salary suggestions and confirmed matches."

  use FirmowidWeb, :html

  alias Phoenix.LiveView.Rendered

  attr :title, :string, required: true
  attr :date_label, :string, required: true
  attr :amount_label, :string, required: true

  slot :candidate, required: true do
    attr :id, :string, required: true
    attr :name, :string
    attr :description, :string
    attr :date, :any, required: true
    attr :amount, :any, required: true
  end

  @doc "Renders the same information, date, amount and confirmation columns for every match candidate."
  @spec candidates(map()) :: Rendered.t()
  def candidates(assigns) do
    ~H"""
    <div class="@container flex flex-col gap-4">
      <h2 class="text-lg/tight font-medium">{@title}</h2>

      <div class="grid grid-cols-[minmax(0,1fr)_repeat(2,minmax(min-content,clamp(4rem,12cqi,7.5rem)))_max-content] gap-x-[clamp(1.5rem,3cqi,2rem)] gap-y-4">
        <div class="col-span-full grid grid-cols-subgrid text-sm/snug text-grey-700">
          <span>{gettext("Information")}</span>
          <span class="text-end">{@date_label}</span>
          <span class="text-end">{@amount_label}</span>
        </div>

        <div
          :for={candidate <- @candidate}
          id={candidate.id}
          class="col-span-full grid grid-cols-subgrid items-center"
        >
          <div class="flex min-w-0 flex-col gap-1">
            <p class="line-clamp-1 font-semibold wrap-anywhere">{candidate.name}</p>
            <p class="line-clamp-2 text-sm/snug wrap-anywhere text-grey-600">
              {candidate.description}
            </p>
          </div>
          <div class="text-end text-nowrap">{candidate.date}</div>
          <div class="text-end text-nowrap tabular-nums">{candidate.amount}</div>
          <div class="flex items-center gap-2">{render_slot(candidate)}</div>
        </div>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :level, :atom, required: true, values: [:high, :mid, :low]
  attr :tooltip, :string, required: true

  @doc "Renders the shared three-bar indicator without assuming how a match was scored."
  @spec score_indicator(map()) :: Rendered.t()
  def score_indicator(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook="Tippy"
      data-tippy-content={@tooltip}
      aria-label={@tooltip}
      role="img"
      class={[
        "flex size-8 shrink-0 flex-col justify-between rounded-md p-2",
        @level == :high && "bg-green-200",
        @level == :mid && "bg-orange-200",
        @level == :low && "bg-red-200"
      ]}
    >
      <div class={[
        "h-0.5 w-full rounded-md",
        if(@level == :high, do: "bg-green-700", else: "bg-white")
      ]} />
      <div class={[
        "h-0.5 w-[70%] rounded-md",
        @level == :high && "bg-green-700",
        @level == :mid && "bg-orange-700",
        @level == :low && "bg-white"
      ]} />
      <div class={[
        "h-0.5 w-[40%] rounded-md",
        @level == :high && "bg-green-700",
        @level == :mid && "bg-orange-700",
        @level == :low && "bg-red-700"
      ]} />
    </div>
    """
  end

  slot :action

  @doc "Renders the confirmed-match heading, complete badge and optional undo action."
  @spec confirmed_header(map()) :: Rendered.t()
  def confirmed_header(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center justify-between gap-4">
      <h2 class="text-lg/tight font-medium">{gettext("Matching")}</h2>
      <div class="flex items-center gap-2">
        <div class="flex items-center self-stretch rounded-md bg-green-200 px-[14.5px]">
          <p class="text-sm/tight font-medium text-green-700">{gettext("Complete")}</p>
        </div>
        {render_slot(@action)}
      </div>
    </div>
    """
  end

  attr :amount, :any, required: true
  attr :amount_label, :string, default: nil
  attr :large_amount?, :boolean, default: true

  slot :heading

  slot :detail, required: true do
    attr :label, :string, required: true
  end

  @doc "Renders matched metadata and the settled amount in the same muted green card."
  @spec confirmed_card(map()) :: Rendered.t()
  def confirmed_card(assigns) do
    ~H"""
    <div class="flex flex-col gap-4 rounded-md bg-green-200/40 p-4">
      {render_slot(@heading)}
      <div class="grid grid-flow-col grid-cols-[2fr_1fr_1fr] grid-rows-2 gap-x-4 gap-y-6">
        <div :for={detail <- @detail} class="flex min-w-0 flex-col gap-1">
          <p class="text-sm/snug text-grey-700">{detail.label}</p>
          <div class="leading-snug wrap-anywhere">{render_slot(detail)}</div>
        </div>
        <div class="row-span-2 flex flex-col items-end justify-end gap-1 text-end">
          <p :if={@amount_label} class="text-sm/snug text-grey-700">{@amount_label}</p>
          <p class={["leading-snug text-green-700", @large_amount? && "text-lg"]}>{@amount}</p>
        </div>
      </div>
    </div>
    """
  end
end
