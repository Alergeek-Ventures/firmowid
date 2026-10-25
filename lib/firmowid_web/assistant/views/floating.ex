defmodule FirmowidWeb.Assistant.Views.Floating do
  @moduledoc "A nonmodal LiveView assistant that keeps its conversation across product navigation."
  use FirmowidWeb, :live_view

  alias Firmowid.Ash.Assistant
  alias FirmowidUI.Components.Button
  alias FirmowidUI.Components.Link
  alias FirmowidWeb.Assistant.Utilities.Presentation
  alias FirmowidWeb.Infrastructure.Hooks.RequireOrganization

  @impl true
  def mount(_params, session, socket) do
    socket =
      AshAuthentication.Phoenix.LiveSession.assign_new_resources(socket, session, otp_app: :firmowid)

    case RequireOrganization.on_mount(:default, %{}, session, socket) do
      {:cont, socket} ->
        conversation = Assistant.get_or_create_conversation!(scope: socket.assigns.ash_scope)

        if connected?(socket),
          do: Phoenix.PubSub.subscribe(Firmowid.PubSub, Assistant.topic(conversation.id))

        {:ok,
         socket
         |> assign(open: false, form_error: nil)
         |> assign_conversation(conversation), layout: false}

      {:halt, socket} ->
        {:ok, socket, layout: false}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <aside
      id="firmowid-assistant"
      class="assistant-shell"
      phx-hook="AssistantChat"
      data-storage-key={"assistant:#{@current_user.id}:#{@current_org.id}"}
      data-open={to_string(@open)}
      aria-label={gettext("Firmowid assistant")}
    >
      <section
        id="assistant-panel"
        class="assistant-panel"
        role="dialog"
        aria-labelledby="assistant-heading"
        hidden={!@open}
      >
        <header class="assistant-header">
          <span class="assistant-mark"><Lucideicons.sparkles class="size-5" aria-hidden="true" /></span>
          <div class="flex-1 min-inline-0">
            <h2 id="assistant-heading" class="text-base/tight font-medium">
              {gettext("Firmowid assistant")}
            </h2>
            <p class="mbs-1 truncate text-xs/snug text-grey-700">{@current_org.name}</p>
          </div>
          <Button.button
            type="button"
            variant="ghost"
            size="small"
            class="assistant-icon-button"
            phx-click="close"
            aria-label={gettext("Close assistant")}
          ><Lucideicons.x class="size-5" aria-hidden="true" /></Button.button>
        </header>

        <div
          id="assistant-messages"
          class="assistant-messages"
          role="log"
          aria-live="off"
          aria-label={gettext("Conversation")}
          tabindex="0"
        >
          <div id="assistant-content" class="assistant-content">
            <div :if={@turns == []} class="assistant-empty">
              <div class="assistant-empty-mark">
                <Lucideicons.list_checks class="size-6" aria-hidden="true" />
              </div>
              <h3 class="text-lg/tight font-medium">
                {gettext("Let's put your transactions in order")}
              </h3>
              <p class="text-sm/5 text-grey-700">
                {gettext(
                  "Find payments, check matches and prepare changes. You decide what gets saved."
                )}
              </p>
              <div class="assistant-suggestions">
                <Button.button
                  :for={{key, label} <- suggestions()}
                  type="button"
                  variant="outline"
                  phx-click="suggestion"
                  phx-value-key={key}
                  class="assistant-suggestion"
                >
                  <Lucideicons.search class="size-4 shrink-0" aria-hidden="true" /><span>{label}</span>
                  <Lucideicons.arrow_up_right class="size-4 shrink-0" aria-hidden="true" />
                </Button.button>
              </div>
            </div>

            <article
              :for={turn <- @turns}
              id={turn.id}
              class={["assistant-turn", turn.role == :user && "assistant-turn-user"]}
            >
              <%= if turn.role == :user do %>
                <p class="assistant-user-text">{turn.text}</p>
              <% else %>
                <details
                  :if={turn.tools != []}
                  id={"#{turn.id}-tools"}
                  class="assistant-tools"
                  phx-mounted={JS.ignore_attributes("open")}
                >
                  <summary>
                    <Lucideicons.list_checks class="size-4" aria-hidden="true" /><span>{ngettext(
                      "%{count} step",
                      "%{count} steps",
                      length(turn.tools)
                    )}</span><Lucideicons.chevron_down class="size-4" aria-hidden="true" />
                  </summary>
                  <div class="assistant-tool-list">
                    <.tool_step :for={tool <- turn.tools} tool={tool} />
                  </div>
                </details>
                <div :if={turn.text != ""} class="assistant-markdown">{turn.html}</div>
              <% end %>
            </article>

            <div
              :if={@conversation.status == :running}
              id="assistant-working"
              class="assistant-working"
              aria-busy="true"
            >
              <div class="flex items-center gap-2 text-xs/snug text-grey-700">
                <Lucideicons.loader_circle class="assistant-spinner size-4" aria-hidden="true" />{gettext(
                  "Working on your request"
                )}
              </div>
              <div
                id="assistant-live-text"
                phx-update="ignore"
                class="assistant-live-text"
                aria-hidden="true"
              >
              </div>
            </div>

            <.approval_plan
              :if={@plan.calls != []}
              plan={@plan}
              version={@conversation.version}
            />

            <div :if={@conversation.error} class="assistant-error" role="alert">
              <Lucideicons.circle_alert class="size-5 shrink-0" aria-hidden="true" />
              <div>
                <strong class="text-sm/5">{gettext("The response was interrupted")}</strong><p class="mbs-1 text-sm/5">
                  {failure_message(@conversation.error)}
                </p>
              </div>
            </div>
          </div>
        </div>

        <Button.button
          id="assistant-new-messages"
          type="button"
          variant="outline"
          size="small"
          class="assistant-new-messages"
          hidden
        >
          <Lucideicons.arrow_down class="size-4" aria-hidden="true" />{gettext("New messages")}
        </Button.button>

        <form id="assistant-form" phx-submit="send" class="assistant-composer">
          <p :if={@form_error} class="mbs-1 mbe-2 text-sm/5 text-red-700" role="alert">
            {@form_error}
          </p>
          <p :if={@conversation.status == :awaiting_approval} class="mbe-2 text-xs/5 text-grey-700">
            {gettext("Confirm or reject the plan before sending another message.")}
          </p>
          <div class="assistant-input-row">
            <textarea
              id="assistant-input"
              name="message"
              rows="2"
              maxlength="20000"
              required
              placeholder={gettext("Ask about a transaction or invoice…")}
              aria-label={gettext("Message to the assistant")}
              aria-describedby="assistant-input-hint"
              phx-update="ignore"
            ></textarea>
            <Button.button
              type="submit"
              variant="primary"
              accent="orange"
              class="assistant-icon-button"
              disabled={@conversation.status in [:running, :awaiting_approval]}
              aria-label={gettext("Send message")}
            >
              <Lucideicons.arrow_up class="size-5" aria-hidden="true" />
            </Button.button>
          </div>
          <p id="assistant-input-hint" class="assistant-input-hint">
            {gettext("Enter to send · Shift+Enter for a new line")}
          </p>
        </form>
      </section>

      <Button.button
        id="assistant-launcher"
        type="button"
        variant="special"
        class="assistant-launcher"
        phx-click="open"
        hidden={@open}
        aria-expanded={to_string(@open)}
        aria-controls="assistant-panel"
      >
        <Lucideicons.sparkles class="size-5" aria-hidden="true" />
        <span>{launcher_label(@conversation.status)}</span>
        <span
          :if={@conversation.status == :awaiting_approval}
          class="assistant-unread"
          aria-hidden="true"
        ></span>
      </Button.button>
      <span class="sr-only" role="status">{status_label(@conversation.status)}</span>
    </aside>
    """
  end

  attr :tool, :map, required: true

  defp tool_step(assigns) do
    ~H"""
    <details
      id={"assistant-step-#{@tool.id}"}
      class="assistant-tool-step"
      phx-mounted={JS.ignore_attributes("open")}
    >
      <summary>
        <Lucideicons.circle_check
          :if={@tool.status == :done}
          class="size-4 text-green-700"
          aria-hidden="true"
        />
        <Lucideicons.circle_alert
          :if={@tool.status in [:error, :unknown]}
          class="size-4 text-red-700"
          aria-hidden="true"
        />
        <Lucideicons.circle_minus
          :if={@tool.status == :denied}
          class="size-4 text-grey-600"
          aria-hidden="true"
        />
        <Lucideicons.circle
          :if={@tool.status == :pending}
          class="size-4 text-grey-600"
          aria-hidden="true"
        />
        <span class="flex-1 min-inline-0">{@tool.label}</span>
        <span class="text-xs/snug text-grey-700">{tool_status_label(@tool.status, @tool.summary)}</span>
      </summary>
      <pre>{@tool.details}</pre>
    </details>
    """
  end

  attr :plan, :map, required: true
  attr :version, :integer, required: true

  defp approval_plan(assigns) do
    ~H"""
    <section
      id={"assistant-plan-#{@version}"}
      class="assistant-plan"
      aria-label={gettext("Proposed changes")}
    >
      <div class="flex items-start gap-2">
        <Lucideicons.list_checks class="size-5 shrink-0 text-orange-700" aria-hidden="true" />
        <h3 class="text-sm/5 font-medium">{gettext("Review the changes before confirming")}</h3>
      </div>
      <div class="assistant-plan-operations">
        <div :for={call <- @plan.calls} class="assistant-plan-operation">
          <h4 class="text-sm/5 font-medium">{call.label}</h4>
          <div :for={record <- call.records} class="assistant-record">
            <%= if record do %>
              <div class="flex-1 min-inline-0">
                <p class="text-xs/snug text-grey-700">
                  {record.kind}<span :if={record.date}> · {Calendar.strftime(record.date, "%d.%m.%Y")}</span>
                </p>
                <Link.link
                  kind="text"
                  size="small"
                  navigate={record.path}
                  class="assistant-record-link"
                >
                  <span class="min-inline-0">{record.label}</span><Lucideicons.arrow_up_right
                    class="shrink-0"
                    aria-hidden="true"
                  />
                </Link.link>
                <p class="line-clamp-2 text-xs/5 text-grey-700">{record.description}</p>
              </div>
              <span class={amount_styles(record.amount_tone)}>{record.amount}</span>
            <% else %>
              <p class="text-sm/5 text-red-700">{gettext("This record is no longer available.")}</p>
            <% end %>
          </div>
          <details>
            <summary class="text-xs/5 text-grey-700">{gettext("Technical data")}</summary><pre>{call.details}</pre>
          </details>
        </div>
      </div>
      <p :if={!@plan.available?} class="text-sm/5 text-red-700">
        {gettext("Some records could not be read. Reject this plan and ask for a new one.")}
      </p>
      <p class="text-xs/5 text-grey-700">
        {gettext("Only the changes listed above will be applied.")}
      </p>
      <div class="assistant-plan-actions">
        <Button.button
          type="button"
          variant="secondary"
          size="small"
          phx-click="deny"
          phx-value-version={@version}
          phx-disable-with={gettext("Rejecting…")}
        >{gettext("Reject")}</Button.button>
        <Button.button
          type="button"
          variant="primary"
          accent="orange"
          size="small"
          disabled={!@plan.available?}
          phx-click="approve"
          phx-value-version={@version}
          phx-disable-with={gettext("Confirming…")}
        >{gettext("Confirm plan")}</Button.button>
      </div>
    </section>
    """
  end

  @impl true
  def handle_event("restore", %{"open" => opened}, socket), do: {:noreply, assign(socket, :open, opened == true)}

  def handle_event("open", params, socket) do
    {:noreply,
     socket
     |> assign(:open, true)
     |> push_event("assistant-focus", %{open: true, prompt: params["prompt"]})}
  end

  def handle_event("close", _params, socket) do
    {:noreply, socket |> assign(:open, false) |> push_event("assistant-focus", %{open: false})}
  end

  def handle_event("suggestion", %{"key" => key}, socket) do
    message = suggestions() |> Map.new() |> Map.fetch!(key)
    send_message(message, socket)
  end

  def handle_event("send", %{"message" => message}, socket), do: send_message(String.trim(message), socket)

  def handle_event(decision, %{"version" => version}, socket) when decision in ["approve", "deny"] do
    with {expected, ""} <- Integer.parse(version),
         {:ok, conversation} <-
           Assistant.respond_to_plan(
             socket.assigns.conversation,
             %{
               decision: if(decision == "approve", do: :approve, else: :deny),
               expected_version: expected
             },
             scope: socket.assigns.ash_scope
           ) do
      {:noreply,
       socket
       |> assign(:form_error, nil)
       |> assign_conversation(conversation)
       |> push_event("assistant-focus", %{open: true})}
    else
      {:error, error} -> operation_error(error, socket)
      :error -> {:noreply, changed_conversation(socket)}
      {_expected, _suffix} -> {:noreply, changed_conversation(socket)}
    end
  end

  @impl true
  def handle_info({:assistant_updated, id}, %{assigns: %{conversation: %{id: id}}} = socket) do
    conversation = Assistant.get_conversation!(id, scope: socket.assigns.ash_scope)

    {:noreply, socket |> assign_conversation(conversation) |> push_event("assistant-reset-stream", %{})}
  end

  def handle_info({:assistant_delta, id, text}, %{assigns: %{conversation: %{id: id}}} = socket) do
    {:noreply, push_event(socket, "assistant-token", %{text: text})}
  end

  defp send_message("", socket) do
    {:noreply, assign(socket, :form_error, gettext("Write a message first."))}
  end

  defp send_message(message, socket) do
    params = %{text: message, expected_version: socket.assigns.conversation.version}

    case Assistant.send_message(socket.assigns.conversation, params, scope: socket.assigns.ash_scope) do
      {:ok, conversation} ->
        {:noreply,
         socket
         |> assign(:form_error, nil)
         |> assign_conversation(conversation)
         |> push_event("assistant-sent", %{})}

      {:error, error} ->
        operation_error(error, socket)
    end
  end

  defp operation_error(%Ash.Error.Invalid{}, socket), do: {:noreply, changed_conversation(socket)}

  defp operation_error(%Ash.Error.Forbidden{}, socket) do
    {:noreply, assign(socket, :form_error, failure_message("access_revoked"))}
  end

  defp operation_error(error, _socket), do: raise(Ash.Error.to_error_class(error))

  defp changed_conversation(socket) do
    conversation =
      Assistant.get_conversation!(socket.assigns.conversation.id, scope: socket.assigns.ash_scope)

    socket
    |> assign_conversation(conversation)
    |> assign(
      :form_error,
      gettext("The conversation changed. Review its current state before continuing.")
    )
  end

  defp assign_conversation(socket, conversation) do
    assign(socket,
      conversation: conversation,
      turns: Presentation.turns(conversation),
      plan: Presentation.plan(conversation, socket.assigns.ash_scope)
    )
  end

  defp suggestions do
    [
      {"unmatched", gettext("Find transactions without an invoice")},
      {"skipped", gettext("Show skipped transactions")},
      {"matched", gettext("Check already matched payments")}
    ]
  end

  defp launcher_label(:running), do: gettext("Assistant is working…")
  defp launcher_label(:awaiting_approval), do: gettext("Review changes")
  defp launcher_label(_status), do: gettext("Assistant")
  defp amount_styles(:income), do: "text-sm/5 text-nowrap tabular-nums text-turquoise-700"
  defp amount_styles(:expense), do: "text-sm/5 text-nowrap tabular-nums text-orange-700"
  defp amount_styles(_tone), do: "text-sm/5 text-nowrap tabular-nums"
  defp status_label(:running), do: gettext("Assistant is working on your request.")
  defp status_label(:awaiting_approval), do: gettext("A plan is ready for your decision.")
  defp status_label(:failed), do: gettext("The response was interrupted.")
  defp status_label(:idle), do: gettext("Assistant is ready.")
  defp tool_status_label(:done, nil), do: gettext("Completed")
  defp tool_status_label(:done, summary), do: summary
  defp tool_status_label(:pending, _summary), do: gettext("Waiting")
  defp tool_status_label(:denied, _summary), do: gettext("Not performed")
  defp tool_status_label(:unknown, _summary), do: gettext("Check the result")
  defp tool_status_label(:error, _summary), do: gettext("Error")

  defp failure_message("access_revoked"), do: gettext("Your access changed. Refresh the page before continuing.")

  defp failure_message(_code),
    do:
      gettext("Some changes may already have been saved. Ask me to check the current state before proposing a new plan.")
end
