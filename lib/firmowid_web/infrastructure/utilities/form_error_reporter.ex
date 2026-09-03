defmodule FirmowidWeb.Infrastructure.Utilities.FormErrorReporter do
  @moduledoc """
  Reports unexpected AshPhoenix form submission failures.

  AshPhoenix can convert Ash action errors into form errors through the
  `AshPhoenix.FormData.Error` protocol. This module keeps cross-cutting
  reporting for those protocol implementations in one place.
  """

  alias Ash.Error.Forbidden.Policy
  alias Firmowid.ErrorKind
  alias Firmowid.Sentry

  require Logger

  @authorization_message "Nie udało się zapisać zmian. Odśwież stronę i spróbuj ponownie."

  @doc """
  Reports an Ash policy denial that happened during an AshPhoenix form submit.
  """
  @spec report_policy_denial(%Policy{}) ::
          {:_form, String.t(), Keyword.t()}
  def report_policy_denial(%Policy{} = error) do
    message = "AshPhoenix form submission forbidden for #{resource_action(error)}"

    Logger.error(message)
    capture_exception(error)
    send_toast(@authorization_message)

    {:_form, @authorization_message, []}
  end

  defp resource_action(error) do
    resource = inspect(error.resource || :unknown_resource)
    action = action_name(error.action)

    "#{resource}.#{action}"
  end

  defp action_name(%{name: name}), do: name
  defp action_name(action) when is_atom(action), do: action
  defp action_name(action), do: ErrorKind.classify(action)

  defp capture_exception(error) do
    exception = RuntimeError.exception("AshPhoenix form policy denial")

    Sentry.capture_exception(exception,
      event_source: :ash_phoenix_form,
      tags: %{
        source: "ash_phoenix_form",
        resource: inspect(error.resource || :unknown_resource),
        action: to_string(action_name(error.action))
      }
    )
  rescue
    _sentry_error ->
      Logger.warning("Failed to report AshPhoenix form policy denial to Sentry")
  end

  defp send_toast(message) do
    LiveToast.send_toast(:error, message)
  rescue
    _error ->
      :ok
  catch
    _kind, _reason ->
      :ok
  end
end

defimpl AshPhoenix.FormData.Error, for: Ash.Error.Forbidden.Policy do
  def to_form_error(error) do
    FirmowidWeb.Infrastructure.Utilities.FormErrorReporter.report_policy_denial(error)
  end
end
