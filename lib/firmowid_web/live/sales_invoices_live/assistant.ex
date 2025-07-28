defmodule FirmowidWeb.SalesInvoicesLive.Assistant do
  use FirmowidWeb, :live_component

  alias Firmowid.Invoicing.Matching.SalesInvoiceAssistant
  alias Firmowid.Invoicing.Matching.Assistant.MessagesStorage
  alias Firmowid.Finances
  alias Firmowid.Accounts
  alias Firmowid.Invoicing.Matching.Assistant.Message
  alias FirmowidWeb.Components.Invoicing.Assistant, as: Components

  @impl true
  def update(%{event: {:loading, boolean}}, socket) do
    {:ok, assign(socket, :loading, boolean)}
  end

  def update(%{event: %Message{role: role} = msg}, socket)
      when role in [:function_call, :function_result] and
             msg.payload.name in ["link_sales_invoice_to_transaction", "search_transactions"] do
    socket =
      case msg do
        %Message{
          role: :function_call,
          payload: %{
            name: "link_sales_invoice_to_transaction",
            done: true
          }
        } ->
          transactions = Finances.get_transactions!(msg.payload.args["transaction_ids"])
          msg = Map.put(msg, :transactions, transactions)

          socket
          |> assign(:waiting_for_decision, true)
          |> stream_insert(:messages, msg)

        %Message{
          role: :function_call,
          payload: %{name: "link_sales_invoice_to_transaction", done: false}
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
    Bodyguard.permit!(Firmowid.SalesInvoices, :read_sales_invoice, current_user, invoice)
    conversation_id = SalesInvoiceAssistant.start_conversation(invoice)
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
      |> assign(:current_user, current_user |> Accounts.get_user_with_avatar())

    {:ok, socket}
  end

  @impl true
  def handle_event("send", %{"message" => message}, socket) do
    SalesInvoiceAssistant.send_message_streaming(socket.assigns.conversation_id, message)

    socket =
      socket
      |> assign(:input, "")
      |> assign(:zero_state, false)

    {:noreply, socket}
  end

  def handle_event("accept", _params, socket) do
    invoice = Firmowid.SalesInvoices.get_sales_invoice!(socket.assigns.invoice_id)
    Bodyguard.permit!(Firmowid.SalesInvoices, :update, socket.assigns.current_user, invoice)
    SalesInvoiceAssistant.accept_linking(socket.assigns.conversation_id)

    socket =
      socket
      |> LiveToast.put_toast(:success, "Transakcje zostały dopasowane do faktury")
      |> push_navigate(to: ~p"/sprzedazowe/#{socket.assigns.invoice_id}")

    {:noreply, socket}
  end

  def handle_event("reject", _params, socket) do
    SalesInvoiceAssistant.reject_linking(socket.assigns.conversation_id)

    {:noreply,
     socket
     |> assign(:input, "")
     |> assign(:waiting_for_decision, false)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="assistant-chat relative flex flex-col mx-auto w-full h-[calc(100vh-64px-128px)]">
      <button
        id="chat-close-button"
        phx-hook="Tippy"
        data-tippy-content="Zamknij czat"
        phx-click="close_chat"
        phx-target="#invoice-show"
        class={[
          "text-sm text-grey-700 self-end flex items-center gap-2 hover:text-grey-400 transition-colors mb-4",
          "absolute top-0 right-0 bg-lightGreyBg hover:border-grey-400 border border-transparent rounded p-2 z-10"
        ]}
      >
        <.icon name="hero-x-mark-mini" />
      </button>
      <div
        class="flex flex-col flex-grow gap-12 py-4 pr-4 overflow-y-auto"
        id="messages"
        phx-update="stream"
        phx-hook="ScrollToBottom"
      >
        <div :for={{id, msg} <- @streams.messages} id={id}>
          {Components.message(msg, @myself, current_user: @current_user)}
        </div>
        <%= if @zero_state do %>
          <div class="flex flex-row flex-wrap gap-3 items-center justify-center py-4">
            <%= for possible_message <- [
            "Ta faktura pokrywa wszystkie transakcje z poprzedniego miesiąca",
            "Transakcja za tę fakturę ma inną nazwę kontrahenta",
            "Opłata została wykonana znacznie później niż faktura została wystawiona",
          ] do %>
              <.button
                phx-click="send"
                color="orange"
                class="text-sm text-orangeText bg-orangeBg font-bold hover:text-orangeBg hover:bg-orangeText"
                phx-target={@myself}
                phx-value-message={possible_message}
              >
                {possible_message}
              </.button>
            <% end %>
          </div>
        <% end %>
      </div>

      <Components.input loading={@loading} input={@input} myself={@myself} />

      <div :if={@waiting_for_decision} class="flex flex-col gap-3 items-center mb-8">
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
