defmodule FirmowidWeb.Assistant.Components.Records do
  @moduledoc "Readable subject and approval previews using already-authorized record data."
  use FirmowidWeb, :html

  alias FirmowidUI.Components.Button
  alias FirmowidUI.Components.Link
  alias Phoenix.LiveView.Rendered

  attr :record, :map, required: true
  attr :class, :any, default: nil

  @doc "Renders a record's label, date and amount without exposing internal identifiers."
  @spec preview(map()) :: Rendered.t()
  def preview(assigns) do
    ~H"""
    <div class={["grid grid-cols-[minmax(0,1fr)_auto] items-start gap-x-3 gap-y-0.5", @class]}>
      <%= if @record do %>
        <p class="col-span-full text-xs leading-[1.4] text-grey-600">
          {@record.kind}<span :if={@record.date}> · {Calendar.strftime(@record.date, "%d.%m.%Y")}</span>
        </p>
        <Link.link
          kind="unstyled"
          navigate={@record.path}
          class="group inline-flex items-start justify-start gap-1 justify-self-start text-start text-sm leading-[1.35] font-medium wrap-anywhere whitespace-normal text-grey-900 select-text active:text-grey-700"
        >
          <span class="underline-offset-[.2em] group-hover:underline">{@record.label}</span><Lucideicons.arrow_up_right
            class="mbs-[.1em] size-4 flex-none text-grey-500"
            aria-hidden="true"
          />
        </Link.link>
        <span
          class={[
            "rounded-sm px-1.5 py-0.5 text-sm/5 text-nowrap tabular-nums empty:hidden",
            amount_styles(@record.amount_tone)
          ]}
          data-tone={@record.amount_tone}
        >{@record.amount}</span>
        <p class="col-span-full line-clamp-2 overflow-clip text-xs leading-[1.4] wrap-anywhere text-grey-600">
          {@record.description}
        </p>
      <% else %>
        <p class="text-sm/5 text-brick-700">{gettext("This record is no longer available.")}</p>
      <% end %>
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
      class="flex flex-col gap-3 rounded-lg bg-grey-100 p-3"
      aria-label={gettext("Proposed changes")}
    >
      <h3 class="rounded-sm bg-grey-200 px-3 py-2 text-base/tight font-medium text-grey-700">
        {gettext("Review the changes before confirming")}
      </h3>
      <div :for={call <- @plan.calls} class="flex flex-col gap-2">
        <h4 class="text-sm/snug text-grey-700">{call.label}</h4>
        <.preview :for={record <- call.records} record={record} class="rounded-lg bg-white p-2.5" />
      </div>
      <p :if={!@plan.available?} class="text-sm/snug text-brick-700">
        {gettext("Some records could not be read. Reject this plan and ask for a new one.")}
      </p>
      <p class="text-xs/snug text-grey-700">
        {gettext("Only the changes listed above will be applied.")}
      </p>
      <div class="flex flex-wrap justify-end gap-2">
        <Button.button
          type="button"
          variant="secondary"
          size="small"
          class="pointer-coarse:min-block-11 pointer-coarse:min-inline-11"
          phx-click="deny"
          phx-value-version={@version}
          phx-value-conversation-id={@conversation_id}
          phx-disable-with={gettext("Rejecting…")}
        >{gettext("Reject")}</Button.button>
        <Button.button
          type="button"
          variant="tertiary"
          size="small"
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

  defp amount_styles(:income), do: "bg-teal-200 text-teal-700"
  defp amount_styles(:expense), do: "bg-rust-200 text-rust-700"
  defp amount_styles(_tone), do: "bg-grey-100"
end
