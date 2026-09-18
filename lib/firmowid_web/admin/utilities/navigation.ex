defmodule FirmowidWeb.Admin.Utilities.Navigation do
  @moduledoc """
  Canonical navigation contract for superuser billing routes and query params.
  """

  use FirmowidWeb, :verified_routes

  alias Firmowid.Ash.Billing.Month
  alias Firmowid.Ash.Billing.PlanCatalog
  alias FirmowidWeb.Infrastructure.Utilities.QueryParams

  @list_param_keys ~w(szukaj plan tylko_nadwyzki)
  @detail_param_keys ~w(miesiac)
  @param_atom_keys %{
    "miesiac" => :miesiac,
    "plan" => :plan,
    "szukaj" => :szukaj,
    "tylko_nadwyzki" => :tylko_nadwyzki
  }

  @doc """
  Returns the canonical current billing month.
  """
  @spec current_month() :: Date.t()
  def current_month, do: Month.current()

  @doc """
  Filters query params for the organizations billing list.
  """
  @spec list_params(map()) :: map()
  def list_params(params) when is_map(params), do: take_allowed_params(params, @list_param_keys)

  @doc """
  Filters query params for the organization billing detail page.
  """
  @spec detail_params(map()) :: map()
  def detail_params(params) when is_map(params), do: take_allowed_params(params, @detail_param_keys)

  @doc """
  Parses the search string from list query params.
  """
  @spec parse_search(map()) :: String.t()
  def parse_search(params) when is_map(params) do
    params |> Map.get("szukaj", "") |> to_string() |> String.trim()
  end

  @doc """
  Parses the plan filter from list query params.
  """
  @spec parse_plan(map()) :: PlanCatalog.plan() | nil
  def parse_plan(params) when is_map(params) do
    case Map.get(params, "plan") do
      nil -> nil
      "" -> nil
      raw when is_binary(raw) -> find_plan(raw)
      _ -> nil
    end
  end

  @doc """
  Parses the over-limit-only flag from list query params.
  """
  @spec parse_only_over_limit?(map()) :: boolean()
  def parse_only_over_limit?(params) when is_map(params) do
    Map.get(params, "tylko_nadwyzki") in ["1", "true", "tak"]
  end

  @doc """
  Parses the selected billing month from detail query params.
  """
  @spec parse_month(map()) :: Date.t()
  def parse_month(params) when is_map(params) do
    params
    |> QueryParams.parse_date("miesiac", current_month())
    |> Date.beginning_of_month()
  end

  @doc """
  Builds the canonical billing organizations list path.
  """
  @spec settlements_path(map()) :: String.t()
  def settlements_path(params \\ %{}) when is_map(params) do
    params = list_params(params)
    ~p"/admin/rozliczenia?#{encode_params(params)}"
  end

  @doc """
  Builds the canonical organization billing detail path.
  """
  @spec settlement_path(String.t(), map()) :: String.t()
  def settlement_path(org_id, params \\ %{}) when is_binary(org_id) and is_map(params) do
    params = detail_params(params)
    ~p"/admin/rozliczenia/#{org_id}?#{encode_params(params)}"
  end

  defp find_plan(raw) do
    Enum.find(PlanCatalog.plans(), &(Atom.to_string(&1) == raw))
  end

  defp encode_params(params) do
    params
    |> Map.new(fn
      {key, %Date{} = value} -> {key, value |> Date.beginning_of_month() |> Date.to_iso8601()}
      {key, value} -> {key, value}
    end)
    |> QueryParams.compact()
  end

  defp take_allowed_params(params, allowed_keys) do
    QueryParams.take_allowed_params(params, allowed_keys, @param_atom_keys)
  end
end
