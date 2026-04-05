defmodule FirmowidWeb.Invoicing.CostInvoices.Components.Assistant do
  @moduledoc false
  use FirmowidWeb, :live_component

  alias Firmowid.Accounts
  alias Firmowid.Ash.Finances
  alias Firmowid.Ash.Invoicing.Matching.Assistant.Message
  alias Firmowid.Ash.Invoicing.Matching.Assistant.MessagesStorage
  alias Firmowid.Ash.Invoicing.Matching.CostInvoiceAssistant
  alias FirmowidWeb.Invoicing.Components.Assistant, as: Components

  @impl true
  def update(%{event: {:loading, boolean}}, socket) do
    {:ok, assign(socket, :loading, boolean)}
  end

  def update(%{event: %Message{role: role} = msg}, socket)
      when role in [:function_call, :function_result] and
             msg.payload.name in ["link_cost_invoice_to_transaction", "search_transactions"] do
    socket =
      case msg do
        %Message{
          role: :function_call,
          payload: %{
            name: "link_cost_invoice_to_transaction",
            done: true
          }
        } ->
          transactions =
            Finances.list_transactions!(
              filter: [id: [in: msg.payload.args["transaction_ids"]]],
              tenant: socket.assigns.current_user.organization_id,
              actor: socket.assigns.current_user
            )

          msg = Map.put(msg, :transactions, transactions)

          socket
          |> assign(:waiting_for_decision, true)
          |> stream_insert(:messages, msg)

        %Message{
          role: :function_call,
          payload: %{name: "link_cost_invoice_to_transaction", done: false}
        } ->
          socket

        _ ->
          stream_insert(socket, :messages, msg)
      end

    {:ok, socket}
  end

  def update(%{event: %Message{role: role} = msg}, socket) when role in [:user, :assistant] do
    {:ok, stream_insert(socket, :messages, msg)}
  end

  def update(%{event: %Message{}}, socket), do: {:ok, socket}

  # pseudo mount
  def update(%{invoice: invoice, current_user: current_user}, socket) do
    conversation_id = CostInvoiceAssistant.start_conversation(invoice)
    messages = MessagesStorage.get(conversation_id)

    socket =
      socket
      |> assign(:conversation_id, conversation_id)
      |> assign(:invoice_id, invoice.id)
      |> assign(:input, "")
      |> assign(:loading, false)
      |> stream(:messages, messages)
      |> assign(:waiting_for_decision, false)
      |> assign(:zero_state, true)
      |> assign(:current_user, Accounts.get_user_with_avatar(current_user))

    {:ok, socket}
  end

  @impl true
  def handle_event("send", %{"message" => message}, socket) do
    CostInvoiceAssistant.send_message_streaming(socket.assigns.conversation_id, message)

    socket =
      socket
      |> assign(:input, "")
      |> assign(:zero_state, false)

    {:noreply, socket}
  end

  def handle_event("accept", _params, socket) do
    CostInvoiceAssistant.accept_linking(socket.assigns.conversation_id)

    socket =
      socket
      |> LiveToast.put_toast(:success, "Transakcje zostały dopasowane do faktury")
      |> push_navigate(to: ~p"/kosztowe/#{socket.assigns.invoice_id}")

    {:noreply, socket}
  end

  def handle_event("reject", _params, socket) do
    CostInvoiceAssistant.reject_linking(socket.assigns.conversation_id)

    {:noreply,
     socket
     |> assign(:input, "")
     |> assign(:waiting_for_decision, false)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="assistant-chat relative mx-auto flex size-full flex-col">
      <button
        id="chat-close-button"
        phx-hook="Tippy"
        data-tippy-content="Zamknij czat"
        phx-click="close_chat"
        phx-target="#invoice-show"
        class="bg-lightGreyBg hover:border-grey-400 hover:text-grey-400 text-grey-700 absolute top-0 right-0 z-10 mb-4 flex items-center gap-2 self-end rounded border border-transparent p-2 text-sm transition-colors"
      >
        <.icon name="hero-x-mark-mini" />
      </button>
      <div
        class="flex grow flex-col gap-12 overflow-y-auto py-4 pr-4"
        id="messages"
        phx-update="stream"
        phx-hook="ScrollToBottom"
      >
        <div :for={{id, msg} <- @streams.messages} id={id}>
          {Components.message(msg, @myself, current_user: @current_user)}
        </div>
        <%= if @zero_state do %>
          <div class="flex flex-row flex-wrap items-center justify-center gap-3 py-4">
            <%= for possible_message <- [
            "Ta faktura pokrywa wszystkie transakcje z poprzedniego miesiąca",
            "Transakcja za tę fakturę ma inną nazwę kontrahenta",
            "Opłata została wykonana znacznie później niż faktura została wystawiona",
          ] do %>
              <.button
                phx-click="send"
                color="orange"
                class="bg-orangeBg hover:bg-orangeText hover:text-orangeBg text-orangeText text-sm font-bold"
                phx-target={@myself}
                phx-value-message={possible_message}
              >
                {possible_message}
              </.button>
            <% end %>
          </div>
        <% end %>
      </div>

      <Components.input
        :if={not @waiting_for_decision}
        loading={@loading}
        input={@input}
        myself={@myself}
      />

      <div :if={@waiting_for_decision} class="mb-8 flex flex-col items-center gap-3">
        <p>Połączyć te transakcje z fakturą?</p>
        <div class="grid grid-cols-2 gap-3">
          <.button
            phx-click="reject"
            phx-target={@myself}
            color="light_grey"
            variant="outline"
            class="text-nowrap"
          >
            Szukaj dalej
          </.button>
          <.button phx-click="accept" phx-target={@myself} color="orange">
            Zatwierdź
          </.button>
        </div>
      </div>
    </div>
    """
  end
end
