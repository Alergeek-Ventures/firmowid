defmodule FirmowidWeb.Management.Utilities.Navigation do
  @moduledoc """
  Canonical navigation contract for management routes and query params.
  """

  use FirmowidWeb, :verified_routes

  alias FirmowidWeb.Infrastructure.Utilities.CounterpartyTypeCodec
  alias FirmowidWeb.Infrastructure.Utilities.QueryParams

  @month_key "miesiac"
  @counterparty_invoice_filter_values %{
    "wszystkie" => :all,
    "oplacone" => :paid,
    "nieoplacone" => :unpaid
  }
  @counterparty_invoice_filter_params Map.new(@counterparty_invoice_filter_values, fn {key, value} ->
                                        {value, key}
                                      end)
  @counterparty_param_keys ~w(filtr_faktur powrot_do)
  @counterparties_param_keys ~w(szukaj typ)
  @employees_param_keys ~w(miesiac szukaj)
  @projects_param_keys ~w(miesiac szukaj)
  @show_param_keys ~w(miesiac)
  @param_atom_keys %{
    "filtr_faktur" => :filtr_faktur,
    "powrot_do" => :powrot_do,
    "szukaj" => :szukaj,
    "typ" => :typ,
    "miesiac" => :miesiac
  }

  @type listing_action :: :index | :archive
  @type counterparty_invoice_filter :: :all | :paid | :unpaid

  @doc """
  Returns the canonical current month used by management routes.
  """
  @spec current_month() :: Date.t()
  def current_month, do: Date.beginning_of_month(Date.utc_today())

  @doc """
  Parses the selected month from management query params.
  """
  @spec parse_month(map()) :: Date.t()
  def parse_month(params) when is_map(params) do
    params
    |> QueryParams.parse_date(@month_key, current_month())
    |> Date.beginning_of_month()
  end

  @doc """
  Filters query params for the counterparties listing.
  """
  @spec counterparties_params(map()) :: map()
  def counterparties_params(params) when is_map(params), do: take_allowed_params(params, @counterparties_param_keys)

  @doc """
  Filters query params for the counterparty details page.
  """
  @spec counterparty_params(map()) :: map()
  def counterparty_params(params) when is_map(params), do: take_allowed_params(params, @counterparty_param_keys)

  @doc """
  Returns the canonical return path from a counterparty details page.
  """
  @spec counterparty_return_path(map()) :: String.t()
  def counterparty_return_path(params) when is_map(params) do
    params
    |> Map.get("powrot_do")
    |> counterparties_return_path()
    |> Kernel.||(counterparties_path(:index))
  end

  @doc """
  Resolves a raw counterparty details path into its canonical allowlisted path.
  """
  @spec counterparty_show_return_path(String.t() | nil) :: String.t() | nil
  def counterparty_show_return_path(raw_return_to), do: normalize_counterparty_show_path(raw_return_to)

  @doc """
  Resolves a raw counterparties return path into its canonical allowlisted path.
  """
  @spec counterparties_return_path(String.t() | nil) :: String.t() | nil
  def counterparties_return_path(raw_return_to), do: normalize_counterparty_return_path(raw_return_to)

  @doc """
  Filters query params for the employees listing.
  """
  @spec employees_params(map()) :: map()
  def employees_params(params) when is_map(params), do: take_allowed_params(params, @employees_param_keys)

  @doc """
  Filters query params for the employee details page.
  """
  @spec employee_params(map()) :: map()
  def employee_params(params) when is_map(params), do: take_allowed_params(params, @show_param_keys)

  @doc """
  Filters query params for the projects listing.
  """
  @spec projects_params(map()) :: map()
  def projects_params(params) when is_map(params), do: take_allowed_params(params, @projects_param_keys)

  @doc """
  Filters query params for the project details page.
  """
  @spec project_params(map()) :: map()
  def project_params(params) when is_map(params), do: take_allowed_params(params, @show_param_keys)

  @doc """
  Parses the shared counterparty type query value.
  """
  @spec parse_counterparty_type(String.t() | nil) ::
          CounterpartyTypeCodec.counterparty_type() | nil
  def parse_counterparty_type(raw_value), do: CounterpartyTypeCodec.parse(raw_value)

  @doc """
  Encodes the shared counterparty type query value.
  """
  @spec encode_counterparty_type(CounterpartyTypeCodec.counterparty_type()) :: String.t()
  def encode_counterparty_type(type), do: CounterpartyTypeCodec.encode(type)

  @doc """
  Parses the counterparty invoice-filter query value.
  """
  @spec parse_counterparty_invoice_filter(String.t() | nil) :: counterparty_invoice_filter() | nil
  def parse_counterparty_invoice_filter(raw_value), do: Map.get(@counterparty_invoice_filter_values, raw_value)

  @doc """
  Encodes the counterparty invoice-filter query value.
  """
  @spec encode_counterparty_invoice_filter(counterparty_invoice_filter()) :: String.t()
  def encode_counterparty_invoice_filter(filter), do: Map.get(@counterparty_invoice_filter_params, filter)

  @doc """
  Builds the canonical counterparties path.
  """
  @spec counterparties_path(listing_action(), map()) :: String.t()
  def counterparties_path(live_action, params \\ %{}) when is_map(params) do
    params = counterparties_params(params)

    case live_action do
      :index -> ~p"/zarzadzanie/kontrahenci?#{encode_params(params)}"
      :archive -> ~p"/zarzadzanie/kontrahenci/archiwum?#{encode_params(params)}"
    end
  end

  @doc """
  Builds the canonical employees path.
  """
  @spec employees_path(listing_action(), map()) :: String.t()
  def employees_path(live_action, params \\ %{}) when is_map(params) do
    params = employees_params(params)

    case live_action do
      :index -> ~p"/zarzadzanie/pracownicy?#{encode_params(params)}"
      :archive -> ~p"/zarzadzanie/pracownicy/archiwum?#{encode_params(params)}"
    end
  end

  @doc """
  Builds the canonical employee details path.
  """
  @spec employee_path(Ash.UUID.t() | String.t(), map()) :: String.t()
  def employee_path(employee_id, params \\ %{}) when is_binary(employee_id) and is_map(params) do
    params = employee_params(params)
    ~p"/zarzadzanie/pracownicy/#{employee_id}?#{encode_params(params)}"
  end

  @doc """
  Builds the canonical counterparty creation path.
  """
  @spec counterparty_new_path(map()) :: String.t()
  def counterparty_new_path(params \\ %{}) when is_map(params) do
    params = counterparty_params(params)
    ~p"/zarzadzanie/kontrahenci/dodaj?#{encode_params(params)}"
  end

  @doc """
  Builds the canonical counterparty details path.
  """
  @spec counterparty_path(Ash.UUID.t() | String.t(), map()) :: String.t()
  def counterparty_path(counterparty_id, params \\ %{}) when is_binary(counterparty_id) and is_map(params) do
    params = counterparty_params(params)
    ~p"/zarzadzanie/kontrahenci/#{counterparty_id}?#{encode_params(params)}"
  end

  @doc """
  Builds the canonical counterparty edit path.
  """
  @spec counterparty_edit_path(Ash.UUID.t() | String.t(), map()) :: String.t()
  def counterparty_edit_path(counterparty_id, params \\ %{}) when is_binary(counterparty_id) and is_map(params) do
    params = counterparty_params(params)
    ~p"/zarzadzanie/kontrahenci/#{counterparty_id}/edycja?#{encode_params(params)}"
  end

  @doc """
  Builds the canonical projects path.
  """
  @spec projects_path(listing_action(), map()) :: String.t()
  def projects_path(live_action, params \\ %{}) when is_map(params) do
    params = projects_params(params)

    case live_action do
      :index -> ~p"/zarzadzanie/projekty?#{encode_params(params)}"
      :archive -> ~p"/zarzadzanie/projekty/archiwum?#{encode_params(params)}"
    end
  end

  @doc """
  Builds the canonical project details path.
  """
  @spec project_path(Ash.UUID.t() | String.t(), map()) :: String.t()
  def project_path(project_id, params \\ %{}) when is_binary(project_id) and is_map(params) do
    params = project_params(params)
    ~p"/zarzadzanie/projekty/#{project_id}?#{encode_params(params)}"
  end

  defp encode_params(params) do
    params
    |> Map.new(fn
      {key, %Date{} = value} -> {key, value |> Date.beginning_of_month() |> Date.to_iso8601()}
      {key, value} -> {key, value}
    end)
    |> QueryParams.compact()
  end

  defp normalize_counterparty_return_path(raw_return_to) when is_binary(raw_return_to) do
    case URI.parse(raw_return_to) do
      %URI{
        scheme: nil,
        userinfo: nil,
        host: nil,
        port: nil,
        path: path,
        query: query,
        fragment: nil
      }
      when path in ["/zarzadzanie/kontrahenci", "/zarzadzanie/kontrahenci/archiwum"] ->
        params = URI.decode_query(query || "")

        with true <- Enum.all?(Map.keys(params), &(&1 in @counterparties_param_keys)),
             {:ok, normalized_params} <- normalize_counterparties_return_params(params) do
          counterparties_path(counterparties_live_action(path), normalized_params)
        else
          _other -> nil
        end

      _other ->
        nil
    end
  end

  defp normalize_counterparty_return_path(_raw_return_to), do: nil

  defp normalize_counterparties_return_params(params) do
    Enum.reduce_while(params, {:ok, %{}}, fn
      {"szukaj", value}, {:ok, normalized_params} when is_binary(value) ->
        {:cont, {:ok, Map.put(normalized_params, "szukaj", value)}}

      {"typ", value}, {:ok, normalized_params} when is_binary(value) ->
        case parse_counterparty_type(value) do
          nil ->
            {:halt, :error}

          type ->
            {:cont, {:ok, Map.put(normalized_params, "typ", encode_counterparty_type(type))}}
        end

      _param, _acc ->
        {:halt, :error}
    end)
  end

  defp normalize_counterparty_show_path(raw_return_to) when is_binary(raw_return_to) do
    case URI.parse(raw_return_to) do
      %URI{
        scheme: nil,
        userinfo: nil,
        host: nil,
        port: nil,
        path: path,
        query: query,
        fragment: nil
      } ->
        with {:ok, counterparty_id} <- parse_counterparty_path(path),
             params = URI.decode_query(query || ""),
             true <- map_size(params) == map_size(counterparty_params(params)),
             {:ok, normalized_params} <- normalize_counterparty_show_params(params) do
          counterparty_path(counterparty_id, normalized_params)
        else
          _other -> nil
        end

      _other ->
        nil
    end
  end

  defp normalize_counterparty_show_path(_raw_return_to), do: nil

  defp normalize_counterparty_show_params(params) do
    Enum.reduce_while(params, {:ok, %{}}, fn
      {"filtr_faktur", value}, {:ok, normalized_params} when is_binary(value) ->
        case parse_counterparty_invoice_filter(value) do
          nil ->
            {:halt, :error}

          filter ->
            {:cont,
             {:ok,
              Map.put(
                normalized_params,
                "filtr_faktur",
                encode_counterparty_invoice_filter(filter)
              )}}
        end

      {"powrot_do", value}, {:ok, normalized_params} when is_binary(value) ->
        case counterparties_return_path(value) do
          nil ->
            {:halt, :error}

          return_to ->
            {:cont, {:ok, Map.put(normalized_params, "powrot_do", return_to)}}
        end

      _param, _acc ->
        {:halt, :error}
    end)
  end

  defp parse_counterparty_path("/zarzadzanie/kontrahenci/" <> counterparty_id) do
    with false <- String.contains?(counterparty_id, "/"),
         {:ok, cast_counterparty_id} <- Ecto.UUID.cast(counterparty_id) do
      {:ok, cast_counterparty_id}
    else
      _error -> :error
    end
  end

  defp parse_counterparty_path(_path), do: :error

  defp counterparties_live_action("/zarzadzanie/kontrahenci"), do: :index
  defp counterparties_live_action("/zarzadzanie/kontrahenci/archiwum"), do: :archive

  defp take_allowed_params(params, allowed_keys) do
    Enum.reduce(allowed_keys, %{}, fn key, filtered_params ->
      atom_key = Map.fetch!(@param_atom_keys, key)

      cond do
        Map.has_key?(params, key) ->
          Map.put(filtered_params, key, Map.fetch!(params, key))

        Map.has_key?(params, atom_key) ->
          Map.put(filtered_params, key, Map.fetch!(params, atom_key))

        true ->
          filtered_params
      end
    end)
  end
end
