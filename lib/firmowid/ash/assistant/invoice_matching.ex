defmodule Firmowid.Ash.Assistant.InvoiceMatching do
  @moduledoc """
  Universal assistant orchestration for matching invoices and transactions.

  The runtime is session-based, not page-based. Current UI entry points may seed
  the assistant with a focused invoice, but the underlying assistant can search
  globally and propose many-to-many matches across invoice types.
  """

  alias Ash.Error.Changes.StaleRecord
  alias Ash.Error.Invalid
  alias Firmowid.Ash.Assistant
  alias Firmowid.Ash.Assistant.InvoiceMatching.PendingMatches
  alias Firmowid.Ash.Assistant.InvoiceMatchingAgent
  alias Firmowid.Ash.Assistant.PendingMatch
  alias Firmowid.Ash.Assistant.Session, as: AssistantSession
  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Scope
  alias Jido.AI.Context, as: AIContext

  require Logger

  @assistant_finch Firmowid.Ash.Assistant.Finch
  @agent_timeout_ms 180_000
  @accept_transaction_resources [AssistantSession, CostInvoice, SalesInvoice]

  @type session_entry_context :: map()

  @doc """
  Starts a new universal invoice-matching assistant session.
  """
  @spec start_session(Scope.t(), session_entry_context()) :: {:ok, struct()} | {:error, term()}
  def start_session(%Scope{} = scope, entry_context \\ %{}) do
    Assistant.start_session(entry_context, scope: scope)
  end

  @doc """
  Loads the current assistant session state.
  """
  @spec get_session(Ash.UUID.t(), Scope.t()) :: {:ok, struct()} | {:error, term()}
  def get_session(session_id, %Scope{} = scope) do
    Assistant.get_session(session_id, scope: scope)
  end

  @doc """
  Sends a user message through the Jido-based matching assistant and persists the updated session.
  """
  @spec send_message(Ash.UUID.t(), String.t(), Scope.t()) :: {:ok, struct()} | {:error, term()}
  def send_message(session_id, message, %Scope{} = scope) when is_binary(message) do
    with {:ok, session} <- Assistant.get_session(session_id, scope: scope),
         :ok <- ensure_session_active_for_message(session),
         {:ok, session} <- Assistant.claim_session_processing(session, scope: scope),
         {:ok, pid} <- start_agent(session) do
      try do
        case InvoiceMatchingAgent.ask(pid, message,
               tool_context: tool_context(scope, session),
               llm_opts: [reasoning_effort: :medium],
               stream_timeout_ms: @agent_timeout_ms,
               req_http_options: [
                 finch: @assistant_finch,
                 pool_timeout: @agent_timeout_ms,
                 receive_timeout: @agent_timeout_ms
               ]
             ) do
          {:ok, request} ->
            await_result = InvoiceMatchingAgent.await(request, timeout: @agent_timeout_ms)

            case build_visible_messages(
                   session.messages,
                   message,
                   await_result,
                   current_pending_match(session_id, scope)
                 ) do
              {:ok, messages} ->
                case finalize_turn(session_id, messages, await_result, scope) do
                  {:ok, updated_session} ->
                    {:ok, updated_session}

                  error ->
                    maybe_persist_error(session_id, scope, error)
                    error
                end

              error ->
                maybe_persist_error(session_id, scope, error)
                error
            end

          error ->
            maybe_persist_error(session_id, scope, error)
            error
        end
      after
        maybe_stop_agent(pid)
      end
    end
  end

  @doc """
  Accepts the pending many-to-many match proposal for a session.
  """
  @spec accept_pending_match(Ash.UUID.t(), Scope.t()) :: {:ok, struct()} | {:error, term()}
  def accept_pending_match(session_id, %Scope{} = scope) do
    Ash.transact(@accept_transaction_resources, fn ->
      with {:ok, session} <- Assistant.get_session(session_id, scope: scope),
           :ok <- ensure_session_waiting_confirmation(session),
           %PendingMatch{} = pending_match <- session.pending_match,
           {:ok, _results} <- PendingMatches.apply(pending_match, scope),
           messages =
             append_message(session.messages, %{
               "role" => "assistant",
               "content" => "Połączyłem wskazane faktury z wybranymi transakcjami."
             }),
           {:ok, updated_session} <-
             Assistant.accept_session_match(
               session,
               messages,
               scope: scope
             ) do
        updated_session
      else
        nil -> {:error, :no_pending_match}
        error -> error
      end
    end)
  end

  @doc """
  Rejects the pending match proposal and keeps the conversation active.
  """
  @spec reject_pending_match(Ash.UUID.t(), Scope.t()) :: {:ok, struct()} | {:error, term()}
  def reject_pending_match(session_id, %Scope{} = scope) do
    with {:ok, session} <- Assistant.get_session(session_id, scope: scope),
         :ok <- ensure_session_waiting_confirmation(session) do
      messages =
        append_message(session.messages, %{
          "role" => "assistant",
          "content" => "OK, nie łączę tych pozycji. Możemy szukać dalej."
        })

      Assistant.reject_session_match(
        session,
        messages,
        scope: scope
      )
    end
  end

  @doc """
  Closes a session and clears any pending confirmation state.
  """
  @spec close_session(Ash.UUID.t(), Scope.t()) :: {:ok, struct()} | {:error, term()}
  def close_session(session_id, %Scope{} = scope) do
    with {:ok, session} <- Assistant.get_session(session_id, scope: scope) do
      case session.status do
        :closed -> {:ok, session}
        _status -> Assistant.close_session(session, scope: scope)
      end
    end
  end

  @doc """
  Builds a reusable entry context for a focused invoice launch point.
  """
  @spec entry_context_for_invoice(struct()) :: map()
  def entry_context_for_invoice(invoice) do
    %{
      "focused_entities" => [invoice_ref(invoice)],
      "title" => "Dopasowanie faktury do transakcji"
    }
  end

  defp start_agent(session) do
    context =
      [system_prompt: session.system_prompt]
      |> AIContext.new()
      |> AIContext.append_messages(session.messages || [])

    with {:ok, pid} <-
           Jido.AgentServer.start_link(
             agent: InvoiceMatchingAgent,
             initial_state: %{context: context}
           ),
         :ok <- register_tools(pid) do
      {:ok, pid}
    end
  end

  defp register_tools(pid) do
    Enum.reduce_while(tool_modules(), :ok, fn tool_module, :ok ->
      case Jido.AI.register_tool(pid, tool_module) do
        {:ok, _agent} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp tool_modules do
    Enum.map(
      [
        ["Firmowid", "Ash", "Assistant", "Actions", "Calculate"],
        ["Firmowid", "Ash", "Assistant", "Actions", "ReadTransactions"],
        ["Firmowid", "Ash", "Assistant", "Actions", "ReadCostInvoices"],
        ["Firmowid", "Ash", "Assistant", "Actions", "ReadSalesInvoices"],
        ["Firmowid", "Ash", "Assistant", "Actions", "NormalizeToPln"],
        ["Firmowid", "Ash", "Assistant", "Actions", "ProposeInvoiceTransactionMatch"],
        ["Firmowid", "Ash", "Assistant", "Actions", "ReadCostInvoiceById"],
        ["Firmowid", "Ash", "Assistant", "Actions", "ReadSalesInvoiceById"]
      ],
      &Module.concat/1
    )
  end

  defp tool_context(scope, session) do
    %{
      session_id: session.id,
      scope: scope,
      actor: scope.actor,
      tenant: scope.actor.organization_id,
      authorize?: true
    }
  end

  defp current_pending_match(session_id, scope) do
    case Assistant.get_session(session_id, scope: scope) do
      {:ok, session} -> session.pending_match
      _ -> nil
    end
  end

  defp build_visible_messages(messages, user_message, {:ok, result}, pending_match) do
    messages = messages |> List.wrap() |> ensure_user_message(user_message)

    cond do
      is_binary(result) and String.trim(result) != "" ->
        {:ok, append_message(messages, %{"role" => "assistant", "content" => result})}

      match?(%PendingMatch{}, pending_match) ->
        {:ok, messages}

      true ->
        Logger.warning("Assistant request completed without a visible response")
        {:error, :empty_assistant_response}
    end
  end

  defp build_visible_messages(messages, user_message, _await_result, _pending_match) do
    {:ok, messages |> List.wrap() |> ensure_user_message(user_message)}
  end

  defp finalize_turn(session_id, persisted_messages, {:ok, _result}, scope) do
    with {:ok, session} <- Assistant.get_session(session_id, scope: scope) do
      case session do
        %{status: :processing, pending_match: nil} ->
          Assistant.complete_session_turn(session, persisted_messages, scope: scope)

        %{status: :waiting_confirmation, pending_match: %PendingMatch{}} ->
          Assistant.sync_pending_session_turn(session, persisted_messages, scope: scope)

        %{status: :closed} ->
          {:error, :session_closed}

        %{status: :errored} ->
          {:error, :session_errored}

        %{status: status} ->
          {:error, {:unexpected_session_status, status}}
      end
    end
  end

  defp finalize_turn(session_id, persisted_messages, {:error, :timeout}, scope) do
    case Assistant.get_session(session_id, scope: scope) do
      {:ok, %{status: :waiting_confirmation, pending_match: %PendingMatch{}} = session} ->
        Assistant.sync_pending_session_turn(session, persisted_messages, scope: scope)

      {:ok, _session} ->
        {:error, :timeout}

      error ->
        error
    end
  end

  defp finalize_turn(_session_id, _persisted_messages, {:error, reason}, _scope), do: {:error, reason}

  defp ensure_session_active_for_message(%{status: :active}), do: :ok

  defp ensure_session_active_for_message(%{status: :processing}), do: {:error, :session_processing}

  defp ensure_session_active_for_message(%{status: :waiting_confirmation}), do: {:error, :waiting_confirmation}

  defp ensure_session_active_for_message(%{status: :closed}), do: {:error, :session_closed}
  defp ensure_session_active_for_message(%{status: :errored}), do: {:error, :session_errored}

  defp ensure_session_waiting_confirmation(%{status: :waiting_confirmation}), do: :ok

  defp ensure_session_waiting_confirmation(%{status: status}), do: {:error, {:invalid_session_status, status}}

  defp ensure_user_message(messages, message) do
    messages ++ [%{"role" => "user", "content" => message}]
  end

  defp maybe_persist_error(session_id, scope, error) do
    with false <- stale_record_error?(error),
         {:ok, %{status: :processing} = session} <-
           Assistant.get_session(session_id, scope: scope) do
      report_error_to_sentry(error, session)

      Assistant.fail_session(
        session,
        inspect(error),
        scope: scope
      )
    else
      true -> :ok
      _ -> :ok
    end
  end

  defp stale_record_error?(%StaleRecord{}), do: true

  defp stale_record_error?(%Invalid{errors: errors}) when is_list(errors) do
    Enum.any?(errors, &stale_record_error?/1)
  end

  defp stale_record_error?(_error), do: false

  defp report_error_to_sentry(error, session) do
    Sentry.capture_exception(RuntimeError.exception("Invoice matching assistant failed"),
      tags: %{
        source: "invoice_matching_assistant"
      },
      extra: %{
        assistant_type: session.assistant_type,
        error: inspect(error),
        organization_id: session.organization_id,
        session_id: session.id,
        status: session.status,
        user_id: session.user_id
      }
    )
  rescue
    sentry_error ->
      Logger.warning("Failed to report assistant error to Sentry: #{Exception.message(sentry_error)}")
  end

  defp maybe_stop_agent(pid) when is_pid(pid) do
    GenServer.stop(pid, :normal)
  catch
    :exit, _ -> :ok
  end

  defp append_message(messages, message), do: (messages || []) ++ [message]

  defp invoice_ref(%CostInvoice{id: id}), do: %{type: :cost_invoice, id: id}

  defp invoice_ref(%SalesInvoice{id: id}), do: %{type: :sales_invoice, id: id}
end
