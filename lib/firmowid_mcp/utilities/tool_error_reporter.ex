defmodule FirmowidMcp.Utilities.ToolErrorReporter do
  @moduledoc """
  Reports unexpected failures behind AshAi tool calls.

  AshAi returns every failed tool call to the client as an error result, so an exception
  raised inside an action never reaches the crash handlers. Ash wraps such exceptions in
  `Ash.Error.Unknown.UnknownError`, which AshAi turns into tool text through the
  `AshAi.ToToolError` protocol.
  """

  alias Ash.Error.Unknown.UnknownError
  alias Firmowid.Sentry

  @doc "Captures the unknown error in Sentry and returns AshAi's generic tool message."
  @spec report_unknown_error(UnknownError.t()) :: String.t()
  def report_unknown_error(%UnknownError{} = error) do
    Sentry.capture_exception(error,
      stacktrace: error.stacktrace && error.stacktrace.stacktrace,
      event_source: :ash_ai_tool,
      tags: %{source: "ash_ai_tool"}
    )

    "unexpected error occurred"
  end
end

defimpl AshAi.ToToolError, for: Ash.Error.Unknown.UnknownError do
  def to_tool_error(error), do: FirmowidMcp.Utilities.ToolErrorReporter.report_unknown_error(error)
end
