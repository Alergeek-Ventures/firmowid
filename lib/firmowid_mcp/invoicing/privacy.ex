defmodule FirmowidMcp.Invoicing.Privacy do
  @moduledoc "Excludes buyer PESEL from MCP contracts and payloads without changing stored invoices."

  @fields ["pesel", "buyer_pesel", "effective_buyer_pesel"]

  @doc "Rejects PESEL arguments before AshAi executes an action."
  @spec validate_arguments(%AshAi.Tool{}, map(), map()) :: {:ok, map()} | {:error, String.t()}
  def validate_arguments(_tool, arguments, _context) do
    if contains_pesel?(arguments) do
      {:error, "Unsupported MCP field: buyer_pesel"}
    else
      {:ok, arguments}
    end
  end

  @doc "Removes PESEL from schemas and optionally restricts buyer input to companies."
  @spec schema(term(), boolean()) :: term()
  def schema(value, business_only?) when is_map(value) do
    value
    |> Map.drop(@fields)
    |> Map.new(fn
      {"required", fields} ->
        {"required", fields -- @fields}

      {"buyer_type", definition} when business_only? ->
        {"buyer_type",
         definition
         |> Map.delete("anyOf")
         |> Map.merge(%{"type" => "string", "enum" => ["company"]})}

      {key, value} ->
        {key, schema(value, business_only?)}
    end)
  end

  def schema(value, business_only?) when is_list(value), do: Enum.map(value, &schema(&1, business_only?))

  def schema(value, _business_only?), do: value

  @doc "Removes PESEL from structured results and their JSON text representation, including corrections."
  @spec result(map()) :: map()
  def result(result) do
    Map.new(result, fn
      {"structuredContent", value} -> {"structuredContent", redact(value)}
      {"content", blocks} -> {"content", Enum.map(blocks, &redact_content/1)}
      pair -> pair
    end)
  end

  defp contains_pesel?(value) when is_map(value) do
    Enum.any?(value, fn {key, value} -> key in @fields or contains_pesel?(value) end)
  end

  defp contains_pesel?(value) when is_list(value), do: Enum.any?(value, &contains_pesel?/1)
  defp contains_pesel?(_value), do: false

  defp redact(value) when is_map(value) do
    value |> Map.drop(@fields) |> Map.new(fn {key, value} -> {key, redact(value)} end)
  end

  defp redact(value) when is_list(value), do: Enum.map(value, &redact/1)
  defp redact(value), do: value

  defp redact_content(%{"type" => "text", "text" => text} = block) do
    case Jason.decode(text) do
      {:ok, value} -> Map.put(block, "text", value |> redact() |> Jason.encode!())
      {:error, _not_json} -> block
    end
  end

  defp redact_content(block), do: block
end
