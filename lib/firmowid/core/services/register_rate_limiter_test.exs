defmodule Firmowid.Core.Services.RegisterRateLimiterTest do
  use ExUnit.Case, async: true

  alias Firmowid.Core.Services.RegisterRateLimiter

  test "parallel processes take turns of one register's limit", %{test: name} do
    start_supervised!({RegisterRateLimiter, name: name, limits: %{ceidg: %{every_ms: 50, max_wait_ms: 1_000}}})

    start = System.monotonic_time(:millisecond)

    released =
      1..3
      |> Enum.map(fn _process ->
        Task.async(fn ->
          :ok = RegisterRateLimiter.acquire(:ceidg, name)
          System.monotonic_time(:millisecond)
        end)
      end)
      |> Task.await_many()
      |> Enum.sort()

    for {at, turn} <- Enum.with_index(released), do: assert(at >= start + turn * 50)
  end

  test "refuses a request whose turn is further away than the longest wait", %{test: name} do
    start_supervised!({RegisterRateLimiter, name: name, limits: %{ceidg: %{every_ms: 60_000, max_wait_ms: 1_000}}})

    assert :ok = RegisterRateLimiter.acquire(:ceidg, name)
    assert {:error, :rate_limited} = RegisterRateLimiter.acquire(:ceidg, name)
  end

  test "refuses requests of all processes once the daily quota is used up", %{test: name} do
    start_supervised!({RegisterRateLimiter, name: name, limits: %{mf_search: %{per_day: 2}}})

    results =
      1..3
      |> Enum.map(fn _process ->
        Task.async(fn -> RegisterRateLimiter.acquire(:mf_search, name) end)
      end)
      |> Task.await_many()

    assert Enum.sort(results) == [:ok, :ok, {:error, :rate_limited}]
    assert {:error, :rate_limited} = RegisterRateLimiter.acquire(:mf_search, name)
  end
end
