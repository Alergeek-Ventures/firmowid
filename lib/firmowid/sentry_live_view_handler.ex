defmodule Firmowid.SentryLiveViewHandler do
  @moduledoc """
  Captures LiveView and LiveComponent exceptions via telemetry with full
  app-frame stacktraces and reports them to Sentry.

  Phoenix LiveView wraps lifecycle callbacks in `:telemetry.span/3`, which
  catches exceptions and emits `[:phoenix, :live_view, *, :exception]` events
  **before** re-raising. At that point, `__STACKTRACE__` still contains the
  real call chain including application frames.

  By contrast, after the re-raise the LiveView GenServer process crashes and
  the resulting Erlang crash report (picked up by `Sentry.LoggerHandler`) may
  only contain framework-internal frames — especially when Ash replaces the
  BEAM stacktrace with its own Splode-captured one.

  This module bridges that gap for `mount`, `handle_params`, `handle_event`,
  `render`, and LiveComponent callbacks. `handle_info` has no telemetry span
  in Phoenix LiveView and still relies on `Sentry.LoggerHandler`.

  Sentry's built-in event deduplication (`:dedup_events`, enabled by default
  in v12) prevents the same exception from being reported twice when both this
  handler and `LoggerHandler` fire for the same crash.

  ## References

  - Phoenix LiveView telemetry: https://hexdocs.pm/phoenix_live_view/telemetry.html
  - Ash stacktrace issue: https://elixirforum.com/t/62934
  - Real-world pattern: https://gist.github.com/sax/2028fa6f8059cc4e0336fb890380f267
  """

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

  @doc """
  Attaches the telemetry handler. Call once during application startup.
  """
  @spec setup :: :ok | {:error, :already_exists}
  def setup do
    :telemetry.attach_many(
      @handler_id,
      @events,
      &__MODULE__.handle_event/4,
      :no_config
    )
  end

  @doc false
  @spec handle_event([atom()], map(), map(), :no_config) :: :ok
  def handle_event(event, _measurements, metadata, :no_config) do
    %{kind: kind, reason: reason, stacktrace: stacktrace} = metadata

    exception = Exception.normalize(kind, reason, stacktrace)

    callback =
      event
      |> Enum.slice(1, 2)
      |> Enum.map_join(".", &Atom.to_string/1)

    Sentry.capture_exception(exception,
      stacktrace: stacktrace,
      event_source: :live_view,
      tags: %{
        source: "live_view_telemetry",
        callback: callback
      },
      extra: build_extra(metadata)
    )

    :ok
  rescue
    # Never crash a telemetry handler — detachment is permanent.
    error ->
      Logger.warning("#{inspect(__MODULE__)} failed to capture exception: #{Exception.message(error)}")

      :ok
  end

  defp build_extra(metadata) do
    %{}
    |> maybe_put(:event, metadata[:event])
    |> maybe_put(:params, metadata[:params])
    |> maybe_put(:socket_id, get_in(metadata, [:socket, Access.key(:id)]))
    |> maybe_put(:view, get_in(metadata, [:socket, Access.key(:view)]))
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, inspect(value))
end
