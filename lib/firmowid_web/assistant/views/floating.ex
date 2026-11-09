defmodule FirmowidWeb.Assistant.Views.Floating do
  @moduledoc """
  The assistant LiveView: a nonmodal panel that keeps its conversation across product
  navigation, or the full assistant page (`page` session flag) with the conversation list beside
  the chat. Both restore the tab's conversation, so moving between them continues it.
  """
  use FirmowidWeb, :live_view

  alias Ash.Error.Forbidden
  alias Ash.Error.Invalid
  alias Firmowid.Assistant
  alias FirmowidWeb.Assistant.Components.Controls
  alias FirmowidWeb.Assistant.Components.History
  alias FirmowidWeb.Assistant.Components.Records
  alias FirmowidWeb.Assistant.Components.Transcript
  alias FirmowidWeb.Assistant.Utilities.PageContext
  alias FirmowidWeb.Assistant.Utilities.Presentation
  alias FirmowidWeb.Infrastructure.Hooks.RequireOrganization

  @impl true
  def mount(_params, session, socket) do
    socket =
      AshAuthentication.Phoenix.LiveSession.assign_new_resources(socket, session, otp_app: :firmowid)

    case RequireOrganization.on_mount(:default, %{}, session, socket) do
      {:cont, socket} ->
        page? = session["page"] == true

        socket =
          socket
          |> assign(
            page?: page?,
            page_path: session["page_path"],
            open: page?,
            form_error: nil,
            history_open?: false
          )
          |> load_history()

        # History is ordered by creation; resume the conversation used most recently today.
        conversation =
          case Enum.filter(socket.assigns.history, &Assistant.resumable?/1) do
            [] ->
              nil

            today ->
              latest = Enum.max_by(today, & &1.updated_at, DateTime)
              Assistant.get_conversation!(latest.id, scope: socket.assigns.ash_scope)
          end

        {:ok, select_conversation(socket, conversation), layout: false}

      {:halt, socket} ->
        {:ok, socket, layout: false}
    end
  end

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        conversation_id: client_conversation_id(assigns.conversation),
        conversation_status: if(assigns.conversation, do: assigns.conversation.status, else: :idle),
        conversation_error: assigns.conversation && assigns.conversation.error
      )

    if assigns.page?, do: page(assigns), else: floating(assigns)
  end

  defp page(assigns) do
    ~H"""
    <section
      id="firmowid-assistant"
      class="grid size-full grid-cols-1 bg-white text-sm/normal text-grey-900 block-[calc(100dvh-var(--navbar-height))] md:grid-cols-[18rem_minmax(0,1fr)]"
      phx-hook="AssistantChat"
      data-page
      data-storage-key={"assistant:#{@current_user.id}:#{@current_org.id}"}
      data-open="true"
      data-conversation-id={@conversation_id}
      data-history-open={to_string(@history_open?)}
      aria-label={gettext("Firmowid assistant")}
    >
      <div class={[
        "flex flex-col border-grey-200 min-block-0 md:border-e",
        !@history_open? && "max-md:hidden"
      ]}>
        <Controls.page_history_header history_open?={@history_open?} />
        <History.history
          conversations={@history}
          conversation_id={@conversation_id}
          open={true}
          more?={@history_more?}
        />
      </div>
      <section
        id="assistant-panel"
        class={["flex flex-col min-block-0", @history_open? && "max-md:hidden"]}
        aria-label={gettext("Conversation")}
      >
        <Controls.page_header history_open?={@history_open?} />
        <.conversation
          subject={@subject}
          history_open?={false}
          turns={@turns}
          conversation_id={@conversation_id}
          conversation_status={@conversation_status}
          conversation_error={@conversation_error}
          plan={@plan}
          conversation={@conversation}
          form_error={@form_error}
        />
      </section>
    </section>
    """
  end

  defp floating(assigns) do
    ~H"""
    <aside
      id="firmowid-assistant"
      class="fixed inset-e-(--assistant-inset) inset-be-[calc(var(--assistant-inset)+var(--assistant-bottom-obstruction,0px))] z-40 text-sm/normal text-grey-900 [--assistant-inset:clamp(.5rem,2vw,1.5rem)] max-md:z-50"
      phx-hook="AssistantChat"
      data-storage-key={"assistant:#{@current_user.id}:#{@current_org.id}"}
      data-open={to_string(@open)}
      data-conversation-id={@conversation_id}
      data-history-open={to_string(@history_open?)}
      aria-label={gettext("Firmowid assistant")}
    >
      <section
        id="assistant-panel"
        class="flex flex-col overflow-clip rounded-lg border border-grey-200 bg-white shadow-lg block-160 inline-104 max-block-[calc(100dvh-var(--navbar-height)-2*var(--assistant-inset)-var(--assistant-bottom-obstruction,0px))] max-inline-[calc(100vw-2*var(--assistant-inset))] max-md:fixed max-md:inset-0 max-md:inset-be-(--assistant-bottom-obstruction,0px) max-md:rounded-none max-md:border-0 max-md:block-auto max-md:inline-auto max-md:max-block-none max-md:max-inline-none"
        role="dialog"
        aria-label={gettext("Firmowid assistant")}
        hidden={!@open}
      >
        <Controls.header history_open?={@history_open?} page_path={@page_path} />

        <History.history
          conversations={@history}
          conversation_id={@conversation_id}
          open={@history_open?}
          more?={@history_more?}
        />
        <.conversation
          subject={@subject}
          history_open?={@history_open?}
          turns={@turns}
          conversation_id={@conversation_id}
          conversation_status={@conversation_status}
          conversation_error={@conversation_error}
          plan={@plan}
          conversation={@conversation}
          form_error={@form_error}
        />
      </section>

      <Controls.launcher open={@open} status={@conversation_status} />
    </aside>
    """
  end

  # The subject, transcript and composer, identical in the panel and on the page.
  defp conversation(assigns) do
    ~H"""
    <section
      :if={@subject && !@history_open?}
      class="flex-none border-be border-grey-200 bg-grey-100 px-4 py-3"
      aria-label={gettext("Conversation about")}
    >
      <Records.preview record={@subject.record} />
    </section>
    <Transcript.transcript
      turns={@turns}
      subject={@subject}
      conversation_id={@conversation_id}
      status={@conversation_status}
      error={@conversation_error}
      history_open?={@history_open?}
    >
      <Records.approval_plan
        :if={@plan.calls != []}
        plan={@plan}
        version={@conversation.version}
        conversation_id={@conversation_id}
      />
    </Transcript.transcript>
    <Controls.composer
      conversation_id={@conversation_id}
      status={@conversation_status}
      form_error={@form_error}
      history_open?={@history_open?}
    />
    """
  end

  @impl true
  def handle_event("restore", %{"open" => opened, "conversation_id" => id}, socket) do
    socket = assign(socket, :open, socket.assigns.page? or opened == true)

    case id do
      nil -> {:noreply, socket}
      "new" -> {:noreply, select_conversation(socket, nil)}
      id -> {:noreply, restore_conversation(socket, id)}
    end
  end

  def handle_event("open", _params, socket) do
    {:noreply,
     socket
     |> assign(:open, true)
     |> push_event("assistant-focus", %{open: true})}
  end

  def handle_event("new_conversation", %{"path" => path}, socket) do
    case PageContext.subject(path) do
      nil ->
        {:noreply,
         socket
         |> select_conversation(nil)
         |> assign(:open, true)
         |> push_event("assistant-clear-draft", %{})
         |> push_event("assistant-focus", %{open: true})}

      subject ->
        start_subject_conversation(socket, subject)
    end
  end

  def handle_event("ask", %{"subject_type" => type, "subject_id" => id}, socket) do
    start_subject_conversation(socket, %{subject_type: type, subject_id: id})
  end

  def handle_event("history", _params, socket) do
    socket = if socket.assigns.history_open?, do: socket, else: load_history(socket)
    {:noreply, assign(socket, :history_open?, !socket.assigns.history_open?)}
  end

  def handle_event("older_conversations", _params, socket) do
    {:noreply, load_history(socket, socket.assigns.history_cursor)}
  end

  def handle_event("select_conversation", %{"id" => id}, socket) do
    case Assistant.get_conversation(id, scope: socket.assigns.ash_scope) do
      {:ok, conversation} ->
        {:noreply,
         socket
         |> select_conversation(conversation)
         |> push_event("assistant-focus", %{open: true})}

      {:error, error} ->
        operation_error(error, socket)
    end
  end

  def handle_event("close", _params, socket) do
    {:noreply, socket |> assign(:open, false) |> push_event("assistant-focus", %{open: false})}
  end

  def handle_event("suggestion", %{"key" => key, "conversation-id" => id}, socket) do
    if id == client_conversation_id(socket.assigns.conversation) do
      message =
        socket.assigns.subject |> Presentation.suggestions() |> Map.new() |> Map.fetch!(key)

      send_message(message, socket)
    else
      {:noreply, changed_conversation(socket)}
    end
  end

  def handle_event("send", %{"message" => message, "conversation_id" => id}, socket) do
    if id == client_conversation_id(socket.assigns.conversation) do
      send_message(String.trim(message), socket)
    else
      {:noreply, changed_conversation(socket)}
    end
  end

  def handle_event(decision, %{"version" => version, "conversation-id" => id}, socket)
      when decision in ["approve", "deny"] do
    with true <- id == client_conversation_id(socket.assigns.conversation) and id != "new",
         {expected, ""} <- Integer.parse(version),
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
      false -> {:noreply, changed_conversation(socket)}
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

  # Messages already in the mailbox can outlive the previous subscription.
  def handle_info({:assistant_updated, _id}, socket), do: {:noreply, socket}
  def handle_info({:assistant_delta, _id, _text}, socket), do: {:noreply, socket}

  defp send_message("", socket) do
    {:noreply, assign(socket, :form_error, gettext("Write a message first."))}
  end

  defp send_message(message, %{assigns: %{conversation: nil}} = socket) do
    case Assistant.start_conversation(%{text: message}, scope: socket.assigns.ash_scope) do
      {:ok, conversation} -> message_sent(socket, conversation)
      {:error, error} -> operation_error(error, socket)
    end
  end

  defp send_message(message, socket) do
    params = %{text: message, expected_version: socket.assigns.conversation.version}

    case Assistant.send_message(socket.assigns.conversation, params, scope: socket.assigns.ash_scope) do
      {:ok, conversation} -> message_sent(socket, conversation)
      {:error, error} -> operation_error(error, socket)
    end
  end

  defp start_subject_conversation(socket, subject) do
    case Assistant.start_subject_conversation(subject, scope: socket.assigns.ash_scope) do
      {:ok, conversation} ->
        {:noreply,
         socket
         |> select_conversation(conversation)
         |> assign(:open, true)
         |> push_event("assistant-focus", %{open: true})}

      {:error, error} ->
        operation_error(error, socket)
    end
  end

  defp message_sent(socket, conversation) do
    source_id = client_conversation_id(socket.assigns.conversation)

    {:noreply,
     socket
     |> select_conversation(conversation)
     |> push_event("assistant-sent", %{conversation_id: conversation.id, source_id: source_id})}
  end

  defp operation_error(%Invalid{}, socket), do: {:noreply, changed_conversation(socket)}

  defp operation_error(%Forbidden{}, socket) do
    {:noreply, assign(socket, :form_error, Presentation.failure_message("access_revoked"))}
  end

  defp operation_error(error, _socket), do: raise(Ash.Error.to_error_class(error))

  defp changed_conversation(socket) do
    conversation =
      if socket.assigns.conversation,
        do:
          Assistant.get_conversation!(socket.assigns.conversation.id,
            scope: socket.assigns.ash_scope
          )

    socket
    |> assign_conversation(conversation)
    |> assign(
      :form_error,
      gettext("The conversation changed. Review its current state before continuing.")
    )
  end

  # A tab's conversation last used on an earlier day is not restored: the one mount resumed stays.
  defp restore_conversation(socket, id) do
    case Assistant.get_conversation(id, scope: socket.assigns.ash_scope) do
      {:ok, conversation} ->
        if Assistant.resumable?(conversation),
          do: select_conversation(socket, conversation),
          else: socket

      {:error, %Invalid{}} ->
        select_conversation(socket, nil)

      {:error, %Forbidden{}} ->
        select_conversation(socket, nil)

      {:error, error} ->
        raise Ash.Error.to_error_class(error)
    end
  end

  defp select_conversation(socket, conversation) do
    previous = socket.assigns[:conversation]

    if connected?(socket) and
         client_conversation_id(previous) != client_conversation_id(conversation) do
      if previous, do: Phoenix.PubSub.unsubscribe(Firmowid.PubSub, Assistant.topic(previous.id))

      if conversation,
        do: Phoenix.PubSub.subscribe(Firmowid.PubSub, Assistant.topic(conversation.id))
    end

    socket |> assign(history_open?: false, form_error: nil) |> assign_conversation(conversation)
  end

  defp assign_conversation(socket, nil) do
    assign(socket,
      conversation: nil,
      subject: nil,
      turns: [],
      plan: %{available?: true, calls: []}
    )
  end

  defp assign_conversation(socket, conversation) do
    messages =
      Assistant.list_messages!(%{conversation_id: conversation.id},
        scope: socket.assigns.ash_scope,
        page: false
      )

    conversation = %{conversation | messages: messages}

    assign(socket,
      conversation: conversation,
      subject: Presentation.subject(conversation, socket.assigns.ash_scope),
      turns: Presentation.turns(conversation),
      plan: Presentation.plan(conversation, socket.assigns.ash_scope),
      history: put_history_entry(socket.assigns.history, conversation)
    )
  end

  # Keeps the always visible list on the page current without reloading its loaded pages.
  defp put_history_entry(history, conversation) do
    if Enum.any?(history, &(&1.id == conversation.id)),
      do: Enum.map(history, &if(&1.id == conversation.id, do: conversation, else: &1)),
      else: [conversation | history]
  end

  defp client_conversation_id(nil), do: "new"
  defp client_conversation_id(conversation), do: conversation.id

  defp load_history(socket, cursor \\ nil) do
    pagination = if cursor, do: [limit: 20, after: cursor], else: [limit: 20]

    page =
      Assistant.list_conversations!(
        scope: socket.assigns.ash_scope,
        query: [select: [:id, :title, :status, :inserted_at, :updated_at]],
        page: pagination
      )

    # The open conversation may already be listed above its page; list it once.
    history =
      if cursor do
        listed = MapSet.new(socket.assigns.history, & &1.id)
        socket.assigns.history ++ Enum.reject(page.results, &MapSet.member?(listed, &1.id))
      else
        page.results
      end

    last = List.last(page.results)

    assign(socket,
      history: history,
      history_more?: page.more?,
      history_cursor: if(last, do: last.__metadata__.keyset)
    )
  end
end
