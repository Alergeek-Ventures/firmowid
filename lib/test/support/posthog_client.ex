defmodule Firmowid.Test.Support.PosthogClient do
  @moduledoc "Process-local PostHog substitute used by deterministic tests."

  @doc "Returns the process-local fake client configuration."
  @spec config() :: %{enabled: boolean()}
  def config, do: %{enabled: Process.get({__MODULE__, :enabled}, false)}

  @doc "Records a capture message when the fake client is enabled."
  @spec bare_capture(String.t(), String.t(), map()) :: :ok | :error
  def bare_capture(event, distinct_id, properties) do
    if config().enabled do
      send(
        Process.get({__MODULE__, :receiver}, self()),
        {:posthog_capture, event, distinct_id, properties}
      )

      :ok
    else
      :error
    end
  end

  @doc "Enables the fake client and sends captures to the given process."
  @spec enable() :: :ok
  @spec enable(pid()) :: :ok
  def enable(receiver \\ self()) do
    Process.put({__MODULE__, :enabled}, true)
    Process.put({__MODULE__, :receiver}, receiver)
    :ok
  end

  @doc "Disables the fake client for the current process."
  @spec disable() :: :ok
  def disable do
    Process.delete({__MODULE__, :enabled})
    Process.delete({__MODULE__, :receiver})
    :ok
  end
end
