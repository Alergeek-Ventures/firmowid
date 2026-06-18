defmodule Firmowid.Test.Support.ResendTestAdapter do
  @moduledoc """
  Swoosh adapter for test environments that behaves like `Swoosh.Adapters.Test`
  but returns a fake Resend-compatible response with an `:id` field.
  """

  use Swoosh.Adapter

  @impl Swoosh.Adapter
  def deliver(email, _config) do
    for pid <- pids() do
      send(pid, {:email, email})
    end

    {:ok, %{id: "resend-test-fake-#{System.unique_integer([:positive])}"}}
  end

  @impl Swoosh.Adapter
  def deliver_many(emails, _config) do
    for pid <- pids() do
      send(pid, {:emails, emails})
    end

    responses =
      for _email <- emails do
        %{id: "resend-test-fake-#{System.unique_integer([:positive])}"}
      end

    {:ok, responses}
  end

  defp pids do
    if pid = Application.get_env(:swoosh, :shared_test_process) do
      [pid]
    else
      Enum.uniq([self() | List.wrap(Process.get(:"$callers"))])
    end
  end
end
