defmodule Firmowid.SentryFilter do
  @moduledoc """
  Filters noisy Sentry log events.

  Used to drop successful `/health` request logs from Sentry while keeping
  failing health checks and all other request logs.
  """

  @doc """
  Drops `/health` log events with HTTP status 200.
  """
  @spec before_send_log(Sentry.LogEvent.t()) :: Sentry.LogEvent.t() | nil
  def before_send_log(%Sentry.LogEvent{attributes: attrs} = log_event) do
    request_path = get_attr_value(attrs, "request_path")
    status = get_attr_value(attrs, "status")

    if request_path == "/health" and status in [200, "200"] do
      nil
    else
      log_event
    end
  end

  @spec get_attr_value(map(), String.t()) :: term()
  defp get_attr_value(attrs, key) do
    case Map.get(attrs, key) do
      %{value: value} -> value
      value -> value
    end
  end
end
