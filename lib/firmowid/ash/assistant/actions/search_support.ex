defmodule Firmowid.Ash.Assistant.Actions.SearchSupport do
  @moduledoc false

  @default_limit 20

  @doc """
  Applies a shared default limit and clamps user-provided limits.
  """
  @spec normalized_limit(integer() | nil, pos_integer()) :: pos_integer()
  def normalized_limit(nil, max_limit), do: min(@default_limit, max_limit)

  def normalized_limit(limit, max_limit) when is_integer(limit) and limit > 0, do: min(limit, max_limit)

  def normalized_limit(_limit, max_limit), do: min(@default_limit, max_limit)

  @doc """
  Parses an optional ISO8601 date string.
  """
  @spec parse_date(String.t() | nil) :: {:ok, Date.t() | nil} | {:error, String.t()}
  def parse_date(nil), do: {:ok, nil}
  def parse_date(""), do: {:ok, nil}

  def parse_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      {:error, _reason} -> {:error, "Nieprawidłowy format daty. Użyj YYYY-MM-DD."}
    end
  end

  @doc """
  Parses an optional numeric input into Decimal.
  """
  @spec parse_decimal(String.t() | integer() | float() | Decimal.t() | nil) ::
          {:ok, Decimal.t() | nil} | {:error, String.t()}
  def parse_decimal(nil), do: {:ok, nil}
  def parse_decimal(""), do: {:ok, nil}
  def parse_decimal(%Decimal{} = value), do: {:ok, value}
  def parse_decimal(value) when is_integer(value), do: {:ok, Decimal.new(value)}
  def parse_decimal(value) when is_float(value), do: {:ok, Decimal.from_float(value)}

  def parse_decimal(value) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, ""} -> {:ok, decimal}
      _ -> {:error, "Nieprawidłowy format kwoty. Użyj liczby."}
    end
  end

  def parse_decimal(_value), do: {:error, "Nieprawidłowy format kwoty. Użyj liczby."}

  @doc """
  Ensures an assistant search uses at least one narrowing filter.
  """
  @spec require_narrowing_filter(map(), [atom()]) :: :ok | {:error, String.t()}
  def require_narrowing_filter(params, keys) do
    if Enum.any?(keys, &present?(Map.get(params, &1))) do
      :ok
    else
      {:error, "Podaj przynajmniej jeden filtr zawężający wyszukiwanie."}
    end
  end

  @doc """
  Parses an optional string enum into an atom.
  """
  @spec parse_enum(String.t() | atom() | nil, map(), String.t()) ::
          {:ok, atom() | nil} | {:error, String.t()}
  def parse_enum(nil, _mapping, _field_name), do: {:ok, nil}
  def parse_enum("", _mapping, _field_name), do: {:ok, nil}

  def parse_enum(value, mapping, field_name) when is_atom(value),
    do: parse_enum(Atom.to_string(value), mapping, field_name)

  def parse_enum(value, mapping, field_name) when is_binary(value) do
    case Map.fetch(mapping, value) do
      {:ok, parsed_value} -> {:ok, parsed_value}
      :error -> {:error, "Nieprawidłowa wartość pola #{field_name}."}
    end
  end

  @doc """
  Drops nil and blank-string values from an argument map.
  """
  @spec compact_args(map()) :: map()
  def compact_args(args) do
    Enum.reduce(args, %{}, fn
      {_key, nil}, compacted -> compacted
      {_key, ""}, compacted -> compacted
      {key, value}, compacted -> Map.put(compacted, key, value)
    end)
  end

  @doc """
  Returns whether a value meaningfully narrows a query.
  """
  @spec present?(term()) :: boolean()
  def present?(value), do: value not in [nil, false, "", []]
end
