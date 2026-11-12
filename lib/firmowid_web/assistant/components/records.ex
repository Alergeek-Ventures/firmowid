defmodule FirmowidWeb.Assistant.Components.Records do
  @moduledoc "Dense record rows for answers, subjects and approval previews, from already-authorized data."
  use FirmowidWeb, :html

  alias FirmowidUI.Components.Button
  alias FirmowidUI.Components.Link
  alias Phoenix.LiveView.Rendered

  attr :record, :map, required: true
  attr :class, :any, default: nil

  @doc "Renders a record's label, kind, date and amount without exposing internal identifiers."
  @spec preview(map()) :: Rendered.t()
  def preview(assigns) do
    ~H"""
    <div class={["@container", @class]}>
      <%= if @record do %>
        <.row amount={@record.amount} amount_tone={@record.amount_tone}>
          <:title>
            <Link.link
              :if={@record.path}
              kind="unstyled"
              navigate={@record.path}
              class="text-grey-900 underline decoration-transparent underline-offset-[.2em] select-text hover:decoration-current active:text-grey-700"
            >{@record.label}</Link.link>
            <span :if={!@record.path}>{@record.label}</span>
          </:title>
          <:meta>{meta(@record)}</:meta>
        </.row>
      <% else %>
        <p class="py-2 text-sm/5 text-brick-700">{gettext("This record is no longer available.")}</p>
      <% end %>
    </div>
    """
  end

  attr :records, :map, required: true, doc: "A record list from `Presentation` answer blocks."

  @doc "Renders an answer's record list; a long one shows its first rows and expands in place."
  @spec record_list(map()) :: Rendered.t()
  def record_list(assigns) do
    {visible, rest} =
      if assigns.records.collapse?,
        do: Enum.split(assigns.records.rows, assigns.records.visible),
        else: {assigns.records.rows, []}

    assigns = assign(assigns, visible: visible, rest: rest)

    ~H"""
    <div id={@records.id} class="@container flex flex-col">
      <div class="flex flex-col divide-y divide-grey-200">
        <.answer_row :for={row <- @visible} row={row} />
      </div>
      <div
        :if={@rest != []}
        id={"#{@records.id}-rest"}
        class="flex flex-col divide-y divide-grey-200 border-bs border-grey-200"
        hidden
      >
        <.answer_row :for={row <- @rest} row={row} />
      </div>
      <%!-- The list's own last row, under the same divider, not a separate action. --%>
      <Button.button
        :if={@rest != []}
        type="button"
        variant="unstyled"
        class="group flex cursor-pointer items-center gap-1 border-bs border-grey-200 text-start text-sm font-medium text-grey-900 inline-full min-block-10 active:opacity-80"
        aria-expanded="false"
        aria-controls={"#{@records.id}-rest"}
        phx-click={
          JS.toggle_attribute({"hidden", ""}, to: "##{@records.id}-rest")
          |> JS.toggle_attribute({"aria-expanded", "true", "false"})
        }
      >
        <span class="underline-offset-[.2em] group-aria-expanded:hidden pointer-fine:group-hover:underline">
          {ngettext("Show %{count} more row", "Show %{count} more rows", length(@rest))}
        </span>
        <span class="hidden underline-offset-[.2em] group-aria-expanded:inline pointer-fine:group-hover:underline">
          {gettext("Collapse the list")}
        </span>
        <Lucideicons.chevron_down
          class="size-3.5 group-aria-expanded:rotate-180 motion-safe:transition-transform motion-safe:duration-200 motion-safe:ease-out"
          aria-hidden="true"
        />
      </Button.button>
    </div>
    """
  end

  attr :pick, :map, required: true, doc: "A pick list from `Presentation` answer blocks."
  attr :conversation_id, :string, required: true
  attr :active?, :boolean, required: true, doc: "Whether the question is still open."

  @doc """
  Renders the candidates the assistant asks the user to choose from, best first: date,
  counterparty and title, the evidence with caveats in rust, and the amount. Choosing one sends
  it as the next message.
  """
  @spec pick_list(map()) :: Rendered.t()
  def pick_list(assigns) do
    ~H"""
    <div id={@pick.id} class="@container flex flex-col divide-y divide-grey-200">
      <Button.button
        :for={candidate <- @pick.candidates}
        type="button"
        variant="unstyled"
        class="group -mx-2 grid cursor-pointer grid-cols-[1.25rem_minmax(0,1fr)_auto_auto] items-baseline gap-x-3 rounded-none p-2 text-start text-sm font-normal whitespace-normal select-none [grid-template-areas:'r_c_y_a'] first:rounded-t-md last:rounded-b-md active:enabled:bg-grey-100 disabled:cursor-default disabled:opacity-100 @max-[37.5rem]:grid-cols-[1.25rem_minmax(0,1fr)_auto] @max-[37.5rem]:gap-y-0.5 @max-[37.5rem]:[grid-template-areas:'r_c_a''r_y_y'] pointer-fine:enabled:hover:bg-grey-50 phx-click-loading:bg-grey-100"
        phx-click="pick"
        phx-value-choice={candidate.choice}
        phx-value-conversation-id={@conversation_id}
        disabled={!@active?}
      >
        <Lucideicons.circle
          class="size-4 self-center text-grey-400 [grid-area:r] group-enabled:pointer-fine:group-hover:text-grey-700"
          aria-hidden="true"
        />
        <span class="truncate text-grey-600 [grid-area:c]">
          <span class="inline-block text-grey-900 tabular-nums min-inline-[3.3em]">{candidate.date}</span>
          <span class="font-medium text-grey-900">{candidate.counterparty}</span>
          <span aria-hidden="true"> · </span>{candidate.title}
        </span>
        <span class="text-xs text-grey-700 [grid-area:y] @min-[37.5rem]:text-nowrap [&_em]:text-rust-700 [&_em]:not-italic">
          {candidate.evidence}
        </span>
        <span
          class={[
            "justify-self-end rounded-sm px-1.5 py-0.5 text-sm/5 font-medium text-nowrap tabular-nums [grid-area:a]",
            amount_styles(candidate.amount_tone)
          ]}
          data-tone={candidate.amount_tone}
        >{candidate.amount}</span>
      </Button.button>
    </div>
    """
  end

  attr :row, :map, required: true

  defp answer_row(assigns) do
    ~H"""
    <.row amount={@row.amount} amount_tone={@row.amount_tone}>
      <:title>
        <span class="[&_a]:underline [&_a]:decoration-grey-300 [&_a]:underline-offset-[.2em]">{@row.title}</span>
      </:title>
      <:meta>
        <%= for {cell, index} <- Enum.with_index(@row.meta) do %>
          <span :if={index > 0} aria-hidden="true"> · </span>{cell}
        <% end %>
      </:meta>
    </.row>
    """
  end

  attr :amount, :any, default: nil
  attr :amount_tone, :atom, default: nil
  slot :title, required: true
  slot :meta

  @doc "Renders one dense row: title, details and the amount at the end, two lines when narrow."
  @spec row(map()) :: Rendered.t()
  def row(assigns) do
    ~H"""
    <div class="grid grid-cols-[minmax(0,1fr)_minmax(0,.85fr)_minmax(7.5em,auto)] items-baseline gap-x-4 py-2 [grid-template-areas:'t_m_a'] @max-[31.25rem]:grid-cols-[minmax(0,1fr)_auto] @max-[31.25rem]:gap-y-px @max-[31.25rem]:[grid-template-areas:'t_a''m_m']">
      <p class="truncate text-sm font-medium text-grey-900 [grid-area:t]">{render_slot(@title)}</p>
      <p class="truncate text-xs text-grey-600 [grid-area:m]">{render_slot(@meta)}</p>
      <span
        :if={@amount}
        class={[
          "justify-self-end rounded-sm px-1.5 py-0.5 text-sm/5 font-medium text-nowrap tabular-nums [grid-area:a]",
          amount_styles(@amount_tone)
        ]}
        data-tone={@amount_tone}
      >{@amount}</span>
    </div>
    """
  end

  attr :plan, :map, required: true
  attr :version, :integer, required: true
  attr :conversation_id, :string, required: true

  @doc "Renders the exact plan and version submitted by the approval controls."
  @spec approval_plan(map()) :: Rendered.t()
  def approval_plan(assigns) do
    ~H"""
    <section
      id={"assistant-plan-#{@version}"}
      class="flex flex-col gap-3 rounded-lg border border-grey-200 px-4 pbs-3.5 pbe-4"
      aria-label={gettext("Proposed changes")}
    >
      <div :for={call <- @plan.calls} class="flex flex-col gap-1">
        <h4 class="text-sm/snug font-semibold text-grey-900">{call.label}</h4>
        <div
          :if={call.records != []}
          class="flex flex-col divide-y divide-grey-200 border-y border-grey-200"
        >
          <.preview :for={record <- call.records} record={record} />
        </div>
        <.changes :if={call.changes != []} changes={call.changes} />
        <p :if={call.unchanged?} class="text-sm/snug text-brick-700">
          {gettext("This changes nothing. Reject the plan.")}
        </p>
      </div>
      <p :if={!@plan.readable?} class="text-sm/snug text-brick-700">
        {gettext("Some records could not be read. Reject this plan and ask for a new one.")}
      </p>
      <div class="flex flex-wrap items-center justify-end gap-2">
        <p class="me-auto text-xs/snug text-grey-600">
          {gettext("Only the changes listed above will be applied.")}
        </p>
        <Button.button
          type="button"
          variant="ghost"
          class="pointer-coarse:min-block-11 pointer-coarse:min-inline-11"
          phx-click="deny"
          phx-value-version={@version}
          phx-value-conversation-id={@conversation_id}
          phx-disable-with={gettext("Rejecting…")}
        >{gettext("Reject")}</Button.button>
        <Button.button
          type="button"
          variant="secondary"
          class="pointer-coarse:min-block-11 pointer-coarse:min-inline-11"
          disabled={!@plan.available?}
          phx-click="approve"
          phx-value-version={@version}
          phx-value-conversation-id={@conversation_id}
          phx-disable-with={gettext("Confirming…")}
        >{gettext("Confirm plan")}</Button.button>
      </div>
    </section>
    """
  end

  attr :changes, :list, required: true

  # Each changed field as it was and as it will be; a dash marks no value.
  defp changes(assigns) do
    ~H"""
    <dl class="grid grid-cols-[minmax(0,max-content)_minmax(0,1fr)] gap-x-6 gap-y-1.5 py-1.5 text-sm max-[30rem]:grid-cols-1 max-[30rem]:gap-y-0">
      <%= for change <- @changes do %>
        <dt class="text-grey-600 max-[30rem]:pbs-1.5">{change.label}</dt>
        <dd class="wrap-anywhere min-inline-0">
          <del :if={change.from} class="text-grey-500">{change.from}</del>
          <span :if={!change.from} class="text-grey-400" aria-hidden="true">—</span>
          <Lucideicons.arrow_right
            class="mx-1.5 inline-block size-3.5 -translate-y-px text-grey-400"
            aria-hidden="true"
          />
          <ins :if={change.to} class="font-medium text-grey-900 no-underline">{change.to}</ins>
          <span :if={!change.to} class="text-grey-400">{gettext("none")}</span>
        </dd>
      <% end %>
    </dl>
    """
  end

  defp meta(record) do
    [record.kind, record.date && Calendar.strftime(record.date, "%d.%m.%Y"), record.description]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" · ")
  end

  @doc "Tints income teal and costs rust."
  @spec amount_styles(atom()) :: String.t()
  def amount_styles(:income), do: "bg-teal-200 text-teal-700"
  def amount_styles(:expense), do: "bg-rust-200 text-rust-700"
  def amount_styles(_tone), do: "text-grey-900"
end
