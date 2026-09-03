defmodule Firmowid.Sentry do
  @moduledoc """
  Owns Firmowid's Sentry integration, including privacy filtering and LiveView
  telemetry exception reporting.
  """

  # This module is the application's boundary to the Sentry SDK.
  # credo:disable-for-next-line Checks.RejectDirectSentrySdk
  alias Elixir.Sentry, as: SentrySDK

  require Logger

  @handler_id "#{inspect(__MODULE__)}"
  @events [
    [:phoenix, :live_view, :mount, :exception],
    [:phoenix, :live_view, :handle_params, :exception],
    [:phoenix, :live_view, :handle_event, :exception],
    [:phoenix, :live_view, :render, :exception],
    [:phoenix, :live_component, :handle_event, :exception],
    [:phoenix, :live_component, :update, :exception]
  ]

  @safe_headers ["user-agent"]
  @tag_keys [
    :source,
    :callback,
    :resource,
    :action,
    :stage,
    :error_kind,
    :oban_worker,
    :oban_queue,
    :oban_state
  ]
  @extra_keys [
    :callback,
    :view,
    :assistant_type,
    :error_count,
    :error_kinds,
    :user_id,
    :organization_id,
    :bank_account_id,
    :requisition_id,
    :session_id,
    :error_kind,
    :status,
    :operation
  ]
  @log_keys [
    :request_id,
    :user_id,
    :organization_id,
    :bank_account_id,
    :blob_id,
    :account_id,
    :requisition_id,
    :leave_request_id,
    :digest_id,
    :invoice_id,
    :inbound_email_id,
    :error_kind,
    :details_kind,
    :service,
    :operation,
    :stage,
    :status,
    :attachment_count,
    :bytes,
    :kind,
    :key_count,
    :health_check,
    :mfa
  ]
  @context_fields %{
    os: [:name, :version],
    runtime: [:name, :version],
    trace: [:trace_id, :span_id, :parent_span_id, :op, :status, :origin, :sampled]
  }
  @default_fingerprint "{{ default }}"
  @log_body "Log captured"

  @doc "Attaches the LiveView telemetry exception handler once at application startup."
  @spec setup() :: :ok | {:error, :already_exists}
  def setup, do: :telemetry.attach_many(@handler_id, @events, &__MODULE__.handle_event/4, :no_config)

  @doc "Captures an exception emitted by a LiveView telemetry span."
  @spec handle_event([atom()], map(), map(), :no_config) :: :ok
  def handle_event(event, _measurements, metadata, :no_config) do
    %{kind: kind, reason: reason, stacktrace: stacktrace} = metadata
    exception = Exception.normalize(kind, reason, stacktrace)
    callback = event |> Enum.slice(1, 2) |> Enum.map_join(".", &Atom.to_string/1)

    case capture_exception(exception,
           stacktrace: stacktrace,
           event_source: :live_view,
           tags: %{source: "live_view_telemetry", callback: callback},
           extra: build_extra(metadata, callback)
         ) do
      {:ok, _} ->
        Logger.metadata(sentry_live_view_captured: true)
        SentrySDK.Context.set_extra_context(%{sentry_live_view_captured: true})

      _ ->
        :ok
    end

    :ok
  rescue
    _ ->
      Logger.warning("Firmowid.Sentry failed to capture exception")
      :ok
  catch
    :exit, _reason ->
      Logger.warning("Firmowid.Sentry failed to capture exception")
      :ok
  end

  @doc "Captures an exception through the application's privacy-aware Sentry boundary."
  @spec capture_exception(Exception.t(), keyword()) :: SentrySDK.send_result()
  def capture_exception(exception, options \\ []), do: SentrySDK.capture_exception(exception, options)

  @doc "Removes private or personally identifying data from an event payload."
  @spec before_send(SentrySDK.Event.t() | SentrySDK.Transaction.t()) ::
          SentrySDK.Event.t() | SentrySDK.Transaction.t() | nil
  def before_send(%SentrySDK.Event{} = event) do
    if live_view_captured?(event), do: nil, else: scrub_event(event)
  rescue
    _ -> nil
  end

  def before_send(%SentrySDK.Transaction{} = transaction) do
    scrub_transaction(transaction)
  rescue
    _ -> nil
  end

  def before_send(_), do: nil

  defp scrub_event(event) do
    %{
      event
      | user: scrub_user(event.user),
        request: scrub_request(event.request),
        transaction: scrub_url_string(event.transaction),
        extra: scrub_extra(event.extra),
        tags: scrub_tags(event.tags),
        contexts: scrub_contexts(event.contexts),
        fingerprint: scrub_fingerprint(event.fingerprint),
        breadcrumbs: scrub_breadcrumbs(event.breadcrumbs),
        exception: scrub_exceptions(event.exception),
        threads: scrub_threads(event.threads),
        message: scrub_event_message(event),
        attachments: []
    }
  end

  @doc "Sanitizes a Sentry log event and drops health-check logs."
  @spec before_send_log(SentrySDK.LogEvent.t()) :: SentrySDK.LogEvent.t() | nil
  def before_send_log(%SentrySDK.LogEvent{attributes: attributes} = event) when is_map(attributes) do
    if attributes[:health_check] in [true, "true"] or not application_log_mfa?(attributes) do
      nil
    else
      %{
        event
        | body: @log_body,
          template: nil,
          parameters: nil,
          attributes: scrub_log_attributes(attributes)
      }
    end
  rescue
    _ -> nil
  end

  def before_send_log(_), do: nil

  @doc "Discards request body and retains no request body data in Plug context."
  @spec scrub_body(Plug.Conn.t()) :: map()
  def scrub_body(_conn), do: %{}

  @doc "Retains only non-sensitive request headers."
  @spec scrub_headers(Plug.Conn.t()) :: map()
  def scrub_headers(conn), do: safe_headers(conn.req_headers)

  @doc "Discards all request cookies."
  @spec scrub_cookies(Plug.Conn.t()) :: map()
  def scrub_cookies(_conn), do: %{}

  @doc "Builds a URL retaining scheme, host, and path while removing query and fragment."
  @spec scrub_url(Plug.Conn.t()) :: String.t()
  def scrub_url(conn), do: conn |> Plug.Conn.request_url() |> scrub_url_string()

  defp build_extra(metadata, callback) do
    assigns = get_in(metadata, [:socket, Access.key(:assigns)]) || %{}
    socket = metadata[:socket]

    %{}
    |> put_if_present(:callback, callback)
    |> put_if_present(:view, safe_value(socket && socket.view))
    |> put_if_present(:user_id, safe_value(assigns[:current_user] && assigns[:current_user].id))
    |> put_if_present(
      :organization_id,
      safe_value(assigns[:current_org] && assigns[:current_org].id)
    )
  end

  defp put_if_present(map, _key, nil), do: map
  defp put_if_present(map, key, value), do: Map.put(map, key, value)
  defp safe_value(value) when is_binary(value) or is_number(value) or is_atom(value), do: value
  defp safe_value(_value), do: nil

  defp scrub_user(user) when is_map(user), do: scalar_map(user, [:id, :ip_address])
  defp scrub_user(_user), do: nil

  defp scrub_request(%SentrySDK.Interfaces.Request{} = request) do
    %{
      request
      | url: scrub_url_string(request.url),
        query_string: nil,
        data: nil,
        cookies: nil,
        headers: safe_headers(request.headers),
        env: scrub_env(request.env)
    }
  end

  defp scrub_request(nil), do: nil
  defp scrub_request(_request), do: nil

  defp scrub_url_string(url) when is_binary(url) do
    url
    |> URI.parse()
    |> Map.update!(:path, &scrub_sensitive_route/1)
    |> Map.put(:userinfo, nil)
    |> Map.put(:query, nil)
    |> Map.put(:fragment, nil)
    |> URI.to_string()
  end

  defp scrub_url_string(nil), do: nil
  defp scrub_url_string(_url), do: nil
  defp scrub_sensitive_route(nil), do: nil

  defp scrub_sensitive_route(path),
    do: Regex.replace(~r{(/(?:resetuj-haslo|potwierdz-email|faktura)/)[^/?#]+}, path, "\\1[REDACTED_TOKEN]")

  defp safe_headers(headers) when is_map(headers) do
    Enum.reduce(@safe_headers, %{}, fn key, acc ->
      case Map.fetch(headers, key) do
        {:ok, value} when is_binary(value) -> Map.put(acc, key, value)
        _ -> acc
      end
    end)
  end

  defp safe_headers(headers) when is_list(headers), do: headers |> Map.new() |> safe_headers()
  defp safe_headers(_headers), do: %{}

  defp scrub_env(env) when is_map(env), do: Map.take(env, ~w(REMOTE_ADDR REMOTE_PORT SERVER_NAME SERVER_PORT REQUEST_ID))

  defp scrub_env(_env), do: %{}

  defp scalar_map(map, keys) when is_map(map) do
    Enum.reduce(keys, %{}, fn key, acc ->
      case Map.fetch(map, key) do
        {:ok, value}
        when is_atom(value) or is_binary(value) or is_number(value) or is_boolean(value) ->
          Map.put(acc, key, value)

        _ ->
          acc
      end
    end)
  end

  defp scrub_tags(nil), do: nil
  defp scrub_tags(tags) when is_map(tags), do: scalar_map(tags, @tag_keys)
  defp scrub_tags(_tags), do: %{}
  defp scrub_extra(extra) when is_map(extra), do: scalar_map_or_lists(extra, @extra_keys)
  defp scrub_extra(_extra), do: %{}

  defp scalar_map_or_lists(map, keys) do
    Enum.reduce(keys, %{}, fn key, acc ->
      case allowed_extra_value(map, key) do
        {:ok, value} -> Map.put(acc, key, value)
        :error -> acc
      end
    end)
  end

  defp allowed_extra_value(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} ->
        if scalar?(value) or (key == :error_kinds and flat_scalar_list?(value)),
          do: {:ok, value},
          else: :error

      :error ->
        :error
    end
  end

  defp scalar?(value) when is_atom(value) or is_binary(value) or is_number(value) or is_boolean(value), do: true

  defp scalar?(_value), do: false

  defp flat_scalar_list?(value) when is_list(value), do: Enum.all?(value, &scalar?/1)
  defp flat_scalar_list?(_value), do: false

  defp scrub_contexts(contexts) when is_map(contexts) do
    Enum.reduce(@context_fields, %{}, fn {name, fields}, acc ->
      case Map.fetch(contexts, name) do
        {:ok, value} when is_map(value) -> Map.put(acc, name, scalar_map(value, fields))
        _ -> acc
      end
    end)
  end

  defp scrub_contexts(_contexts), do: %{}

  defp scrub_fingerprint(fingerprint) when is_list(fingerprint),
    do: Enum.filter(fingerprint, &(&1 === @default_fingerprint))

  defp scrub_fingerprint(_fingerprint), do: []

  defp scrub_breadcrumbs(breadcrumbs) when is_list(breadcrumbs) do
    breadcrumbs
    |> Enum.map(fn
      %SentrySDK.Interfaces.Breadcrumb{} = breadcrumb -> %{breadcrumb | message: nil, data: nil}
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp scrub_breadcrumbs(_breadcrumbs), do: []

  defp scrub_exceptions(exceptions) when is_list(exceptions), do: Enum.flat_map(exceptions, &scrub_exception_item/1)

  defp scrub_exceptions(_exceptions), do: []

  defp scrub_exception_item(%SentrySDK.Interfaces.Exception{} = exception),
    do: [
      %{
        exception
        | value: "Exception captured",
          mechanism: scrub_mechanism(exception.mechanism),
          stacktrace: scrub_stacktrace(exception.stacktrace)
      }
    ]

  defp scrub_exception_item(_exception), do: []

  defp scrub_mechanism(%SentrySDK.Interfaces.Exception.Mechanism{} = mechanism),
    do: %{mechanism | data: nil, meta: nil, help_link: nil}

  defp scrub_mechanism(_mechanism), do: nil

  defp scrub_stacktrace(%SentrySDK.Interfaces.Stacktrace{} = stacktrace),
    do: %{stacktrace | frames: scrub_frames(stacktrace.frames)}

  defp scrub_stacktrace(_stacktrace), do: nil

  defp scrub_frames(frames) when is_list(frames),
    do:
      Enum.flat_map(frames, fn
        %SentrySDK.Interfaces.Stacktrace.Frame{} = frame ->
          [%{frame | filename: nil, vars: nil, context_line: nil, pre_context: [], post_context: []}]

        _ ->
          []
      end)

  defp scrub_frames(_frames), do: []

  defp scrub_threads(nil), do: nil

  defp scrub_threads(threads) when is_list(threads),
    do:
      Enum.flat_map(threads, fn
        %SentrySDK.Interfaces.Thread{} = thread ->
          [%{thread | name: nil, state: nil, held_locks: nil, stacktrace: scrub_stacktrace(thread.stacktrace)}]

        _ ->
          []
      end)

  defp scrub_threads(_threads), do: []

  defp scrub_event_message(%SentrySDK.Event{exception: exception}) when is_list(exception) and exception != [], do: nil

  defp scrub_event_message(%SentrySDK.Event{message: %SentrySDK.Interfaces.Message{} = message}),
    do: %{message | message: "Message captured", formatted: "Message captured", params: nil}

  defp scrub_event_message(_event), do: nil

  defp scrub_transaction(transaction) do
    %{
      transaction
      | transaction: scrub_url_string(transaction.transaction),
        tags: scrub_tags(transaction.tags),
        data: %{},
        contexts: scrub_contexts(transaction.contexts),
        spans: scrub_spans(transaction.spans)
    }
  end

  defp scrub_spans(spans) when is_list(spans),
    do:
      Enum.flat_map(spans, fn
        %SentrySDK.Interfaces.Span{} = span ->
          [%{span | description: nil, tags: scrub_tags(span.tags), data: %{}, links: []}]

        _ ->
          []
      end)

  defp scrub_spans(_spans), do: []

  defp live_view_captured?(%SentrySDK.Event{source: source, extra: extra})
       when source in [:logger, :plug, :live_view] and is_map(extra) do
    extra[:sentry_live_view_captured] == true or
      match?(%{sentry_live_view_captured: true}, extra[:logger_metadata])
  end

  defp live_view_captured?(_event), do: false

  defp scrub_log_attributes(attributes) do
    Enum.reduce(@log_keys, %{}, fn key, acc ->
      case Map.fetch(attributes, key) do
        {:ok, value} when key == :mfa ->
          Map.put(acc, key, value)

        {:ok, value}
        when is_atom(value) or is_binary(value) or is_number(value) or is_boolean(value) ->
          Map.put(acc, key, value)

        _ ->
          acc
      end
    end)
  end

  defp application_log_mfa?(%{mfa: {module, function, arity}})
       when is_atom(module) and is_atom(function) and is_integer(arity) and arity >= 0, do: application_module?(module)

  defp application_log_mfa?(_attributes), do: false

  defp application_module?(module) do
    name = Atom.to_string(module)

    name == "Elixir.Firmowid" or String.starts_with?(name, "Elixir.Firmowid.") or
      name == "Elixir.FirmowidWeb" or String.starts_with?(name, "Elixir.FirmowidWeb.")
  end
end
