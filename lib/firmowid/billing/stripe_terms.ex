defmodule Firmowid.Billing.StripeTerms do
  @moduledoc """
  Firmowid's boundary with Stripe: the API calls the billing code makes, and how Firmowid's
  billing terms map onto Stripe's. A plan's recurring price is found by its lookup key
  `firmowid_<plan>_<monthly|yearly>` (gross PLN, no price ids in configuration), amounts
  travel in grosze and Stripe's times are read as Warsaw days.

  Every call reads Stripe's objects as string-keyed maps (`response_as: :map`). Stripe's
  subscription statuses are read as Firmowid's lifecycle (`lifecycle/1`).
  """

  alias Firmowid.Billing.PlanCatalog
  alias Firmowid.LocalDate

  @doc """
  Calls Stripe's API at `path` and returns its answer as a string-keyed map.

  `opts` are the request options, such as `:idempotency_key` for a POST.

  The library's resource functions (`Stripe.Subscription.retrieve/3` and others) are typed to
  return structs even with `response_as: :map`, so Dialyzer rejects every map pattern on their
  answers; the request builder they wrap is typed for maps.
  """
  @spec request(Stripe.API.method(), String.t(), map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def request(method, path, params \\ %{}, opts \\ []) do
    opts
    |> Keyword.put(:response_as, :map)
    |> Stripe.Request.new_request()
    |> Stripe.Request.put_endpoint(path)
    |> Stripe.Request.put_params(params)
    |> Stripe.Request.put_method(method)
    |> Stripe.Request.make_request()
  end

  @doc """
  Reads every page of a Stripe list with `request`, a GET of a path with params (such as
  `&request(:get, &1, &2, api_key: key)`), a hundred objects a page.
  """
  @spec list((String.t(), map() -> {:ok, map()} | {:error, term()}), String.t(), map()) ::
          {:ok, [map()]} | {:error, term()}
  def list(request, path, params \\ %{}), do: list_pages(request, path, Map.put_new(params, :limit, 100), [])

  defp list_pages(request, path, params, acc) do
    case request.(path, params) do
      {:ok, %{"data" => data, "has_more" => true}} ->
        list_pages(
          request,
          path,
          Map.put(params, :starting_after, List.last(data)["id"]),
          acc ++ data
        )

      {:ok, %{"data" => data}} ->
        {:ok, acc ++ data}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc "Returns the active recurring price of a plan for a billing period."
  @spec price(PlanCatalog.offered_plan(), PlanCatalog.billing_period()) ::
          {:ok, map()} | {:error, term()}
  def price(plan, billing_period) do
    lookup_key = lookup_key(plan, billing_period)

    case request(:get, "/v1/prices", %{lookup_keys: [lookup_key], active: true}) do
      {:ok, %{"data" => [price | _rest]}} -> {:ok, price}
      {:ok, _none} -> {:error, "Stripe has no active price with the lookup key #{lookup_key}"}
      {:error, error} -> {:error, error}
    end
  end

  @doc "Returns the plan and billing period a price's lookup key names, or `:error`."
  @spec plan_of(map()) ::
          {:ok, {PlanCatalog.offered_plan(), PlanCatalog.billing_period()}} | :error
  def plan_of(%{"lookup_key" => lookup_key}) do
    keys =
      for plan <- PlanCatalog.paid_plans(),
          period <- PlanCatalog.billing_periods(),
          do: {lookup_key(plan, period), {plan, period}}

    case List.keyfind(keys, lookup_key, 0) do
      {_key, plan_and_period} -> {:ok, plan_and_period}
      nil -> :error
    end
  end

  def plan_of(_price), do: :error

  defp lookup_key(plan, billing_period), do: "firmowid_#{plan}_#{billing_period}"

  @doc """
  Returns what a Stripe subscription status means for the organization: `:live` while the
  customer has the plan (`trialing`, `active`, `past_due`), `:pending` while the first payment
  is still pending (`incomplete`), `:over` once Stripe gave up on it.

  A status Stripe adds later matches no clause and fails, so it gets decided here instead of
  being ignored.
  """
  @spec lifecycle(String.t()) :: :pending | :live | :over
  def lifecycle("incomplete"), do: :pending
  def lifecycle(status) when status in ~w(trialing active past_due), do: :live
  def lifecycle(status) when status in ~w(canceled unpaid incomplete_expired paused), do: :over

  @doc "Converts grosze from Stripe to a PLN amount."
  @spec pln(integer()) :: Decimal.t()
  def pln(grosze), do: grosze |> Decimal.new() |> Decimal.div(100) |> Decimal.round(2)

  @doc "Returns the Warsaw day of a Unix time from Stripe."
  @spec warsaw_date(integer()) :: Date.t()
  def warsaw_date(unix), do: unix |> DateTime.from_unix!() |> LocalDate.of()
end
