defmodule Firmowid.SentryFilter do
  @moduledoc """
  Filters noisy Sentry log events.

  Used to drop `/health` request logs from Sentry.
  """

  @doc """
  Drops `/health` log events.
  """
  @spec before_send_log(Sentry.LogEvent.t()) :: Sentry.LogEvent.t() | nil
  def before_send_log(%Sentry.LogEvent{attributes: attrs} = log_event) do
    health_check = get_attr_value(attrs, "health_check")

    if health_check in [true, "true"] do
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
