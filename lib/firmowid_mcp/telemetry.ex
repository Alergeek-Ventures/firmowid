defmodule FirmowidMcp.Telemetry do
  @moduledoc """
  Reports every MCP tool call to PostHog MCP Analytics as a `$mcp_tool_call` event:
  who called which tool, from which AI client, whether it failed and how long it took.

  The event follows PostHog's contract for servers without an MCP Analytics SDK
  (https://posthog.com/docs/mcp-analytics/installation/other-languages). It carries
  no content: tool arguments, results and error messages hold invoices and
  counterparties, so they never leave the application, and tools get no extra
  `context` argument that the ChatGPT app review would have to accept.

  The calls come from AshAi's `[:ash_ai, :mcp, :tool_call]` telemetry span. The
  client is the app of the OAuth client that `FirmowidMcp.Router` puts in the
  action context, recognised by its metadata document's host like on the consent
  screen, so a client cannot claim to be ChatGPT by its name.
  """

  @events [[:ash_ai, :mcp, :tool_call, :stop], [:ash_ai, :mcp, :tool_call, :exception]]
  @server_name "Firmowid"
  @client_info "io.modelcontextprotocol/clientInfo"
  @protocol_version "io.modelcontextprotocol/protocolVersion"
  # ChatGPT's anonymized conversation id, the same for every call of one chat.
  @chatgpt_conversation "openai/session"

  @doc "Attaches the reporter once at application startup."
  @spec attach() :: :ok | {:error, :already_exists}
  def attach, do: :telemetry.attach_many(__MODULE__, @events, &__MODULE__.handle_event/4, nil)

  @doc "Captures a finished or failed tool call. Never raises: analytics must not break a call."
  @spec handle_event([atom()], map(), map(), nil) :: :ok
  def handle_event([:ash_ai, :mcp, :tool_call, outcome], measurements, metadata, nil) do
    with {user_id, properties} <- tool_call(outcome, measurements, metadata),
         true <- enabled?() do
      PostHog.bare_capture("$mcp_tool_call", user_id, properties)
    end

    :ok
  rescue
    _error -> :ok
  catch
    _kind, _reason -> :ok
  end

  @doc """
  Builds the user ID and the properties of the `$mcp_tool_call` event for an AshAi
  tool call event, or `nil` for a call of a tool the server does not have.
  """
  @spec tool_call(:stop | :exception, map(), map()) :: {String.t(), map()} | nil
  def tool_call(_outcome, _measurements, %{tool: nil}), do: nil

  def tool_call(outcome, %{duration: duration}, %{tool_name: tool_name, actor: %{id: user_id}} = metadata) do
    meta = metadata.request_meta || %{}

    properties =
      Map.reject(
        %{
          "$mcp_source" => "posthog_mcp_analytics",
          "$mcp_server_name" => @server_name,
          "$mcp_tool_name" => tool_name,
          "$mcp_resource_name" => tool_name,
          "$mcp_is_error" => error?(outcome, metadata),
          "$mcp_error_type" => error_type(outcome, metadata),
          "$mcp_duration_ms" => System.convert_time_unit(duration, :native, :millisecond),
          "$session_id" => session_id(metadata.context, meta, metadata.session_id),
          "$mcp_client_name" => client_name(metadata.context, meta),
          "$mcp_protocol_version" => meta[@protocol_version],
          "surface" => "mcp",
          "auth_state" => "identified",
          "$groups" => %{"organization" => to_string(metadata.tenant)}
        },
        fn {_key, value} -> is_nil(value) end
      )

    {to_string(user_id), properties}
  end

  defp error?(:exception, _metadata), do: true
  defp error?(:stop, metadata), do: metadata.is_error

  # PostHog's label for a returned `isError` result, and the exception's module for a crash.
  # Error messages can quote invoices or counterparties, so only the kind is reported.
  defp error_type(:exception, %{reason: %module{}}), do: inspect(module)
  defp error_type(:exception, _metadata), do: "internal"
  defp error_type(:stop, %{is_error: true}), do: "Error"
  defp error_type(:stop, _metadata), do: nil

  # PostHog groups the calls of one conversation by `$session_id`: ChatGPT's own
  # conversation (trusted only from the verified ChatGPT client), else the MCP
  # session, else the call alone. Hashed, as PostHog asks.
  defp session_id(%{mcp_client: :chatgpt}, %{@chatgpt_conversation => conversation}, _session_id)
       when is_binary(conversation), do: hashed_session(conversation)

  defp session_id(_context, _meta, session_id) when is_binary(session_id), do: hashed_session(session_id)

  defp session_id(_context, _meta, _session_id), do: "ses_" <> Ash.UUIDv7.generate()

  defp hashed_session(id) do
    "ses_" <> binary_part(Base.encode16(:crypto.hash(:sha256, id), case: :lower), 0, 32)
  end

  # Recognised apps by their OAuth client; other clients by the name they report,
  # which the 2026-07-28 revision sends with every request.
  defp client_name(%{mcp_client: app}, _meta) when app in [:chatgpt, :claude], do: Atom.to_string(app)

  # PostHog accepts names of at most 256 characters.
  defp client_name(_context, %{@client_info => %{"name" => name}}) when is_binary(name), do: String.slice(name, 0, 256)

  defp client_name(_context, _meta), do: nil

  defp enabled? do
    match?(%{enabled: true}, PostHog.config())
  rescue
    _error -> false
  end
end
