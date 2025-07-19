defmodule FirmowidWeb.CostInvoiceLive.Assistant do
  use FirmowidWeb, :live_component

  alias Firmowid.Invoicing.Matching.Assistant
  alias Firmowid.Invoicing.Matching.Assistant.MessagesStorage
  alias FirmowidWeb.Helpers.TimeFormatter
  alias Firmowid.Finances
  alias Firmowid.Accounts

  @impl true
  def update(%{event: {:loading, boolean}}, socket) do
    {:ok, assign(socket, :loading, boolean)}
  end

  def update(%{event: {:new_message, msg}}, socket) do
    socket =
      if msg.role == :assistant do
        socket
        |> assign(:streaming_message_id, msg.id)
        |> assign(:streaming_message_content, msg.text || "")
      else
        socket
      end

    socket =
      case msg do
        %Firmowid.Invoicing.Matching.Assistant.Message{
          role: :user
        } ->
          stream_insert(socket, :messages, msg)

        %Firmowid.Invoicing.Matching.Assistant.Message{
          role: :assistant
        } ->
          socket
          |> assign(:streaming_message_id, msg.id)
          |> assign(:streaming_message_content, msg.text || "")
          |> stream_insert(:messages, msg)

        %Firmowid.Invoicing.Matching.Assistant.Message{
          role: :function_call,
          payload: %{name: "link_cost_invoice_to_transaction"}
        } ->
          transactions =
            Finances.get_transactions!(msg.payload.args["transaction_ids"])

          msg = Map.put(msg, :transactions, transactions)

          socket
          |> assign(:waiting_for_decision, true)
          |> stream_insert(:messages, msg)

        %Firmowid.Invoicing.Matching.Assistant.Message{
          role: :function_call,
          payload: %{name: "search_transactions"}
        } ->
          stream_insert(socket, :messages, msg)

        %Firmowid.Invoicing.Matching.Assistant.Message{
          role: :function_result,
          payload: %{name: "search_transactions"}
        } ->
          stream_insert(socket, :messages, msg)

        _ ->
          socket
      end

    {:ok, socket}
  end

  def update(%{event: {:stream_token, token}}, socket) do
    id = socket.assigns.streaming_message_id

    socket =
      if id do
        new_content = (socket.assigns.streaming_message_content || "") <> token

        socket
        |> assign(:streaming_message_content, new_content)
        |> stream_insert(:messages, %{
          id: id,
          type: :assistant,
          content: new_content,
          metadata: %{}
        })
      end

    {:ok, socket}
  end

  # pseudo mount
  def update(%{invoice: invoice, current_user: current_user}, socket) do
    conversation_id = Assistant.start_conversation(invoice)

    if connected?(socket) do
      MessagesStorage.subscribe(conversation_id)
    end

    messages = MessagesStorage.get(conversation_id)

    socket =
      socket
      |> assign(:conversation_id, conversation_id)
      |> assign(:invoice_id, invoice.id)
      |> assign(:input, "")
      |> assign(:streaming_message_id, nil)
      |> assign(:streaming_message_content, nil)
      |> assign(:loading, false)
      |> stream(:messages, messages)
      |> assign(:waiting_for_decision, false)
      |> assign(:zero_state, true)
      |> assign(:current_user, current_user |> Accounts.get_user_with_avatar())

    {:ok, socket}
  end

  @impl true
  def handle_event("send", %{"message" => message}, socket) do
    {:ok, pid} = Assistant.send_message_async(socket.assigns.conversation_id, message)

    socket =
      socket
      |> assign(:input, "")
      |> assign(:assistant_pid, pid)
      |> assign(:zero_state, false)

    {:noreply, socket}
  end

  def handle_event("accept", _params, socket) do
    Assistant.accept_linking(socket.assigns.assistant_pid)

    # TODO: convert into reinitialization of the cost_invoice liveview
    Process.sleep(500)

    socket =
      socket
      |> LiveToast.put_toast(:success, "Transakcje zostały dopasowane do faktury")
      |> push_navigate(to: ~p"/kosztowe/#{socket.assigns.invoice_id}")

    {:noreply, socket}
  end

  def handle_event("reject", _params, socket) do
    Assistant.reject_linking(socket.assigns.assistant_pid)

    {:noreply,
     socket
     |> assign(:input, "")
     |> assign(:waiting_for_decision, false)
     |> assign(:streaming_message_id, nil)
     |> assign(:streaming_message_content, nil)}
  end

  # New rendering for Message struct with payload
  @doc """
  Renders a message based on its role and payload. Supports user, assistant, function_call, and function_result.
  """
  def message(%{role: :user, text: text}, _myself, opts) do
    current_user = Keyword.fetch!(opts, :current_user)
    assigns = %{text: text, current_user: current_user}

    ~H"""
    <div class="flex flex-row gap-3 justify-end">
      <p class="px-4 py-2 bg-grey-200 rounded max-w-2xl">{@text}</p>
      <div class="w-10 h-10">
        <.avatar class="size-10">
          <.avatar_image src={@current_user.avatar_url} alt="Avatar" />
          <.avatar_fallback>
            {String.slice(@current_user.email, 0, 1) |> String.upcase()}
          </.avatar_fallback>
        </.avatar>
      </div>
    </div>
    """
  end

  def message(%{role: :assistant, text: text}, _myself, _opts) do
    assigns = %{text: text}

    ~H"""
    <div class="flex flex-row gap-3">
      <img src="/images/logo_firmowid.png" class="w-10 h-10 mt-2" />
      <div class="prose prose-p:p-2 prose-p:text-black prose-p:whitespace-pre-wrap max-w-2xl">
        {render_content(@text)}
      </div>
    </div>
    """
  end

  def message(
        %{
          role: :function_call,
          payload: %{name: "search_transactions", args: %{"filters" => filters}}
        },
        _myself,
        _opts
      ) do
    filters =
      filters
      |> Map.put_new("date_from", nil)
      |> Map.put_new("date_to", nil)
      |> Map.put_new("amount_gt", nil)
      |> Map.put_new("amount_lt", nil)
      |> Map.put_new("currency", nil)
      |> Map.put_new("only_unmatched", true)
      |> Map.put_new("query", nil)

    date_filter =
      [
        if(filters["date_from"], do: "od #{TimeFormatter.format_date(filters["date_from"])}"),
        if(filters["date_to"], do: "do #{TimeFormatter.format_date(filters["date_to"])}")
      ]
      |> Enum.reject(&is_nil/1)
      |> case do
        [] -> nil
        list -> Enum.join(list, " ")
      end

    amount_filter =
      [filters["amount_gt"], filters["amount_lt"]]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" - ")

    assigns = %{filters: filters, date_filter: date_filter, amount_filter: amount_filter}

    ~H"""
    <div class="flex flex-row gap-2 items-center ml-[52px] py-2 px-4 flex-wrap max-w-2xl">
      <p class="text-sm text-nowrap">Szukam transakcji</p>
      <div
        :if={@date_filter}
        class="py-1 px-3 bg-orange-100 text-orange-900 rounded whitespace-nowrap"
      >
        data: <span class="font-semibold">{@date_filter}</span>
      </div>
      <div
        :if={@amount_filter != ""}
        class="py-1 px-3 bg-orange-100 text-orange-900 rounded whitespace-nowrap"
      >
        kwota: <span class="font-semibold">{@amount_filter}</span>
      </div>
      <div
        :if={@filters["currency"]}
        class="py-1 px-3 bg-orange-100 text-orange-900 rounded whitespace-nowrap"
      >
        waluta: <span class="font-semibold">{@filters["currency"]}</span>
      </div>
      <div
        :if={@filters["query"]}
        class="py-1 px-3 bg-orange-100 text-orange-900 rounded whitespace-nowrap"
      >
        fraza: <span class="font-semibold">{@filters["query"]}</span>
      </div>
      <div
        :if={not @filters["only_unmatched"]}
        class="py-1 px-3 bg-orange-100 text-orange-900 rounded whitespace-nowrap"
      >
        również dopasowane
      </div>
    </div>
    """
  end

  def message(
        %{
          role: :function_call,
          payload: %{
            name: "link_cost_invoice_to_transaction",
            args: %{"message" => assistant_message}
          },
          transactions: transactions
        } = message,
        myself,
        _opts
      ) do
    assigns = %{
      id: message.id,
      message: assistant_message,
      transactions: transactions,
      myself: myself
    }

    ~H"""
    <div class="ml-[52px] py-2 px-4 max-w-2xl -mt-12 flex flex-col gap-6">
      <p>{@message}</p>

      <ul class="gap-2 flex flex-col w-full">
        <li
          :for={transaction <- @transactions}
          class="py-1 px-3 flex flex-row gap-4 justify-between items-start bg-grey-50 rounded"
        >
          <div class="grid grid-cols-[min-content,1fr] gap-x-3">
            <span class="text-sm text-grey-700">Nadawca</span>
            <span class="text-black truncate">{transaction.creditor_name}</span>
            <span class="text-sm text-grey-700">Zaksięgowano</span>
            <span class="text-black">{TimeFormatter.format_date(transaction.booking_date)}</span>
          </div>
          <div class="flex flex-row gap-3 items-center">
            {transaction.amount}
            <.icon name="hero-credit-card-micro" class="text-grey-700" />
          </div>
        </li>
      </ul>
    </div>
    """
  end

  def message(%{role: :function_call, payload: %{name: name, args: args}}, _myself, _opts) do
    assigns = %{name: name, args: args}

    ~H"""
    <div class="flex flex-row gap-4 items-center">
      <div>🛠️ <b>{@name}</b> called</div>
      <div><pre>{inspect(@args)}</pre></div>
    </div>
    """
  end

  def message(
        %{role: :function_result, payload: %{name: name, result: result}},
        _myself,
        _opts
      ) do
    assigns = %{name: name, result: result}

    case {name, result} do
      {"search_transactions", list} when is_list(list) ->
        text =
          case length(list) do
            0 -> "Nie znalazłem żadnych transakcji"
            1 -> "Znalazłem 1 transakcję"
            count when count < 5 -> "Znalazłem #{count} transakcje"
            count -> "Znalazłem #{count} transakcji"
          end

        assigns = Map.put(assigns, :text, text)

        ~H"""
        <div class="flex flex-row gap-2 items-center ml-[52px] py-2 px-4 flex-wrap -mt-12">
          <p class="text-sm">{@text}</p>
        </div>
        """

      _ ->
        ~H"""
        <div class="flex flex-row gap-4 items-center">
          <div>🛠️ <b>{@name}</b> result</div>
          <div><pre>{inspect(@result)}</pre></div>
        </div>
        """
    end
  end

  # fallback for unknown roles
  def message(%{role: role, text: text, payload: payload}, _myself, _opts) do
    assigns = %{role: role, text: text, payload: payload}

    ~H"""
    <div>[{to_string(@role)}] {render_content(@text)} {inspect(@payload)}</div>
    """
  end

  def message(%{type: _} = assigns, _myself, _opts) do
    ~H"""
    <div>[{to_string(@type)}] {render_content(@content)} {inspect(@metadata)}</div>
    """
  end

  def render_content(nil), do: "failed to render content"

  def render_content(content) do
    content |> MDEx.to_html!() |> raw()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="assistant-chat relative flex flex-col mx-auto w-full h-full">
      <button
        id="chat-close-button"
        phx-hook="Tippy"
        data-tippy-content="Zamknij czat"
        phx-click="close_chat"
        phx-target="#cost-invoice-show"
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
          {message(msg, @myself, current_user: @current_user)}
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

      <form
        :if={not @waiting_for_decision}
        class="flex flex-row gap-2 border border-grey-300 h-12 py-2 px-4 mx-16 mb-8 rounded-md bg-white"
        phx-submit="send"
        phx-target={@myself}
      >
        <input
          name="message"
          value={@input}
          autocomplete="off"
          placeholder={if @loading, do: "Firmowid myśli...", else: "Napisz swoją wiadomość"}
          disabled={@loading}
          class={[
            "placeholder:text-grey-400 text-black w-full p-0 border-none focus:ring-0",
            "focus:outline-none disabled:opacity-50 disabled:cursor-not-allowed"
          ]}
        />
        <button
          type="submit"
          disabled={@loading}
          class="text-grey-400 disabled:opacity-50 disabled:cursor-not-allowed"
        >
          <%= if @loading do %>
            <.icon name="hero-arrow-path" class="animate-spin" />
          <% else %>
            <.icon name="hero-paper-airplane" />
          <% end %>
        </button>
      </form>

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
