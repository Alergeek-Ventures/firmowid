defmodule FirmowidWeb.Invoicing.Components.InvoiceAssistant do
  @moduledoc false
  use FirmowidWeb, :live_component

  import FirmowidWeb.DesignSystem.Components.Button
  import FirmowidWeb.DesignSystem.Components.CoreComponents, except: [button: 1]
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Ash.Assistant.InvoiceMatching
  alias Firmowid.Ash.Assistant.InvoiceMatching.PendingMatches
  alias FirmowidWeb.Invoicing.Assistant.Components.PendingMatch
  alias FirmowidWeb.Invoicing.Components.Assistant, as: Components

  @default_ui_config %{
    container_class: "assistant-chat relative mx-auto flex size-full flex-col",
    close_button_variant: "unstyled",
    close_button_class:
      "bg-lightGreyBg hover:border-grey-400 hover:text-grey-400 text-grey-700 absolute top-0 right-0 z-10 mb-4 inline-flex cursor-pointer items-center justify-center self-end rounded border border-transparent p-2 text-sm transition",
    close_icon_class: nil,
    messages_class: "flex grow flex-col gap-12 overflow-y-auto py-4 pr-4",
    zero_state_class: "flex flex-row flex-wrap items-center justify-center gap-3 py-4"
  }

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:session_id, nil)
     |> assign(:waiting_for_decision, false)
     |> assign(:pending_match_message, nil)
     |> assign(:pending_invoices, [])
     |> assign(:pending_transactions, [])
     |> stream(:messages, [])}
  end

  @impl true
  def update(%{current_user: current_user, scope: scope} = assigns, socket) do
    current_user = Ash.load!(current_user, [avatar_blob: [:url]], scope: scope)

    assistant_config = Map.merge(@default_ui_config, Map.get(assigns, :assistant_config, %{}))

    {:ok,
     socket
     |> assign(:entry_context, Map.fetch!(assigns, :entry_context))
     |> assign(assistant_config)
     |> assign(:scope, scope)
     |> assign(:current_user, current_user)
     |> assign(:return_path, Map.fetch!(assigns, :return_path))
     |> assign(:close_target, Map.get(assigns, :close_target, "#invoice-show"))
     |> assign(:input, socket.assigns[:input] || "")
     |> assign(:assistant_error, socket.assigns[:assistant_error] || nil)
     |> assign(:loading, socket.assigns[:loading] || false)
     |> assign(:zero_state, socket.assigns[:zero_state] || true)}
  end

  @impl true
  def handle_event("send", %{"message" => message}, socket) do
    case ensure_session(socket) do
      {:ok, socket, session_id} ->
        scope = socket.assigns.scope

        {:noreply,
         socket
         |> assign(:input, message)
         |> assign(:assistant_error, nil)
         |> assign(:loading, true)
         |> assign(:zero_state, false)
         |> start_async(:assistant_response, fn ->
           InvoiceMatching.send_message(session_id, message, scope)
         end)}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(:assistant_error, "Nie udało się rozpocząć sesji asystenta")
         |> LiveToast.put_toast(:error, "Nie udało się rozpocząć sesji asystenta")}
    end
  end

  def handle_event("accept", _params, socket) do
    case InvoiceMatching.accept_pending_match(socket.assigns.session_id, socket.assigns.scope) do
      {:ok, session} ->
        _ = InvoiceMatching.close_session(session.id, socket.assigns.scope)

        socket =
          socket
          |> LiveToast.put_toast(:success, "Dopasowanie zostało zapisane")
          |> push_navigate(to: socket.assigns.return_path)

        {:noreply, socket}

      {:error, _reason} ->
        {:noreply, LiveToast.put_toast(socket, :error, "Nie udało się zapisać dopasowania")}
    end
  end

  def handle_event("reject", _params, socket) do
    case InvoiceMatching.reject_pending_match(socket.assigns.session_id, socket.assigns.scope) do
      {:ok, session} ->
        {:noreply, assign_session(socket, session)}

      {:error, _reason} ->
        {:noreply, LiveToast.put_toast(socket, :error, "Nie udało się odrzucić propozycji")}
    end
  end

  @impl true
  def handle_async(:assistant_response, {:ok, {:ok, session}}, socket) do
    {:noreply,
     socket
     |> assign(:input, "")
     |> assign(:loading, false)
     |> assign_session(session)}
  end

  def handle_async(:assistant_response, {:ok, {:error, _reason}}, socket) do
    {:noreply, handle_assistant_failure(socket)}
  end

  def handle_async(:assistant_response, {:exit, _reason}, socket) do
    {:noreply, handle_assistant_failure(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class={@container_class}>
      <Components.error_banner error={@assistant_error} />
      <.button
        id="chat-close-button"
        phx-hook="Tippy"
        data-tippy-content="Zamknij czat"
        phx-click="close_chat"
        phx-target={@close_target}
        phx-value-session_id={@session_id}
        type="button"
        variant={@close_button_variant}
        class={@close_button_class}
      >
        <.icon name="hero-x-mark-mini" class={@close_icon_class} />
      </.button>
      <div
        class={@messages_class}
        id="messages"
        phx-update="stream"
        phx-hook="ScrollToBottom"
      >
        <div :for={{id, msg} <- @streams.messages} id={id}>
          {Components.message(msg, @myself, current_user: @current_user)}
        </div>
        <%= if @zero_state do %>
          <div class={@zero_state_class}>
            <%= for possible_message <- @suggested_messages do %>
              <FirmowidWeb.DesignSystem.Components.Button.button
                phx-click="send"
                variant="secondary"
                phx-target={@myself}
                phx-value-message={possible_message}
              >
                {possible_message}
              </FirmowidWeb.DesignSystem.Components.Button.button>
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
        <p>{@pending_match_message}</p>
        <div class="flex w-full max-w-2xl flex-col gap-4">
          <section :if={@pending_invoices != []} class="space-y-2">
            <p class="text-grey-700 text-sm font-medium">Faktury do połączenia</p>
            <ul class="flex flex-col gap-2">
              <PendingMatch.invoice_item :for={invoice <- @pending_invoices} invoice={invoice} />
            </ul>
          </section>

          <section :if={@pending_transactions != []} class="space-y-2">
            <p class="text-grey-700 text-sm font-medium">Transakcje do połączenia</p>
            <ul class="flex flex-col gap-2">
              <PendingMatch.transaction_item
                :for={transaction <- @pending_transactions}
                transaction={transaction}
                displayed_party_label={@displayed_party_label}
              />
            </ul>
          </section>
        </div>
        <div class="grid grid-cols-2 gap-3">
          <.button
            phx-click="reject"
            phx-target={@myself}
            variant="outline"
            class="text-nowrap"
          >
            Szukaj dalej
          </.button>
          <.button phx-click="accept" phx-target={@myself}>
            Zatwierdź
          </.button>
        </div>
      </div>
    </div>
    """
  end

  defp assign_session(socket, session) do
    {pending_transactions, pending_invoices, pending_match_error} =
      load_pending_match_entries(session.pending_match, socket.assigns.current_user)

    socket
    |> assign(:session_id, session.id)
    |> assign(:assistant_error, session.last_error || pending_match_error)
    |> assign(:waiting_for_decision, not is_nil(session.pending_match))
    |> assign(:pending_match_message, session.pending_match && session.pending_match.message)
    |> assign(:pending_invoices, pending_invoices)
    |> assign(:pending_transactions, pending_transactions)
    |> stream(:messages, filter_visible_messages(session.messages), reset: true)
  end

  defp ensure_session(%{assigns: %{session_id: session_id}} = socket) when is_binary(session_id) do
    {:ok, socket, session_id}
  end

  defp ensure_session(socket) do
    case InvoiceMatching.start_session(
           socket.assigns.scope,
           socket.assigns.entry_context
         ) do
      {:ok, session} -> {:ok, assign_session(socket, session), session.id}
      error -> error
    end
  end

  defp filter_visible_messages(messages) do
    messages
    |> List.wrap()
    |> Enum.filter(fn
      %{"role" => role} -> role in ["user", "assistant"]
      _ -> false
    end)
    |> Enum.with_index()
    |> Enum.map(fn {message, index} ->
      Map.put(message, :id, "message-#{index}")
    end)
  end

  defp load_pending_match_entries(nil, _current_user), do: {[], [], nil}

  defp load_pending_match_entries(pending_match, current_user) do
    with {:ok, transactions} <- PendingMatches.load_transactions(pending_match, current_user),
         {:ok, invoices} <- PendingMatches.load_invoices(pending_match, current_user) do
      {transactions, invoices, nil}
    else
      {:error, :stale_pending_match} -> {[], [], nil}
      {:error, reason} -> {[], [], reason}
    end
  end

  defp handle_assistant_failure(socket) do
    socket = assign(socket, :loading, false)

    case InvoiceMatching.get_session(socket.assigns.session_id, socket.assigns.scope) do
      {:ok, session} ->
        error_message = Components.assistant_error_message(session.last_error)

        socket
        |> assign_session(session)
        |> LiveToast.put_toast(
          :error,
          error_message || "Nie udało się uzyskać odpowiedzi asystenta"
        )

      {:error, _reason} ->
        socket
        |> assign(:assistant_error, "Nie udało się uzyskać odpowiedzi asystenta")
        |> LiveToast.put_toast(:error, "Nie udało się uzyskać odpowiedzi asystenta")
    end
  end
end
