defmodule Firmowid.Infrastructure.JidoActionErrorJSON do
  @moduledoc """
  JSON-safe normalization for Jido action errors.

  `jido_ai` appends tool results to the LLM run context by calling `Jason.encode!`.
  Some `Jido.Action.Error.*` structs do not implement `Jason.Encoder`, which can
  crash the whole agent turn before the model gets a chance to recover from a
  bad tool call.

  This module converts those errors to the normalized `Jido.Action.Error.to_map/1`
  shape and recursively sanitizes nested values into JSON-safe data.
  """

  alias Jido.Action.Error
  alias Jido.Action.Error.ConfigurationError
  alias Jido.Action.Error.ExecutionFailureError
  alias Jido.Action.Error.Internal.UnknownError
  alias Jido.Action.Error.InternalError
  alias Jido.Action.Error.InvalidInputError
  alias Jido.Action.Error.TimeoutError

  @spec encode_error(struct(), Jason.Encode.opts()) :: iodata()
  def encode_error(error, opts) do
    error
    |> error_to_map()
    |> normalize()
    |> Jason.Encode.map(opts)
  end

  defp error_to_map(%InvalidInputError{} = error) do
    %{
      type: :validation_error,
      message: fallback_message(error, "Invalid input"),
      details:
        error
        |> Map.get(:details, %{})
        |> normalize_details()
        |> maybe_put(:field, Map.get(error, :field))
        |> maybe_put(:value, Map.get(error, :value))
        |> maybe_put(:tool_name, Map.get(error, :tool_name)),
      retryable?: false
    }
  end

  defp error_to_map(%ExecutionFailureError{} = error) do
    %{
      type: :execution_error,
      message: fallback_message(error, "Execution error"),
      details: error |> Map.get(:details, %{}) |> normalize_details(),
      retryable?: false
    }
  end

  defp error_to_map(%TimeoutError{} = error) do
    %{
      type: :timeout,
      message: fallback_message(error, "Timed out"),
      details:
        error
        |> Map.get(:details, %{})
        |> normalize_details()
        |> maybe_put(:timeout, Map.get(error, :timeout)),
      retryable?: true
    }
  end

  defp error_to_map(%ConfigurationError{} = error) do
    %{
      type: :configuration_error,
      message: fallback_message(error, "Configuration error"),
      details: error |> Map.get(:details, %{}) |> normalize_details(),
      retryable?: false
    }
  end

  defp error_to_map(%InternalError{} = error) do
    %{
      type: :internal_error,
      message: fallback_message(error, "Internal error"),
      details: error |> Map.get(:details, %{}) |> normalize_details(),
      retryable?: false
    }
  end

  defp error_to_map(%UnknownError{} = error) do
    %{
      type: :internal_error,
      message: fallback_message(error, "Unknown internal error"),
      details: error |> Map.get(:details, %{}) |> normalize_details(),
      retryable?: false
    }
  end

  defp error_to_map(error), do: Error.to_map(error)

  @spec normalize(term()) :: term()
  def normalize(value) when is_binary(value) or is_number(value) or is_boolean(value) or is_nil(value), do: value

  def normalize(value) when is_atom(value), do: Atom.to_string(value)

  def normalize(value) when is_list(value), do: Enum.map(value, &normalize/1)

  def normalize(%_{} = value) do
    value
    |> Map.from_struct()
    |> Map.delete(:__exception__)
    |> normalize()
  end

  def normalize(value) when is_map(value) do
    Map.new(value, fn {key, nested_value} -> {normalize_key(key), normalize(nested_value)} end)
  end

  def normalize(value) when is_tuple(value), do: value |> Tuple.to_list() |> Enum.map(&normalize/1)

  def normalize(value), do: inspect(value)

  defp normalize_details(details) when is_map(details), do: details
  defp normalize_details(_details), do: %{}

  defp fallback_message(error, fallback) do
    case Map.get(error, :message) do
      message when is_binary(message) and message != "" -> message
      message when is_atom(message) -> Atom.to_string(message)
      nil -> fallback
      other -> inspect(other)
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key), do: key
end

defimpl Jason.Encoder, for: Jido.Action.Error.InvalidInputError do
  def encode(error, opts), do: Firmowid.Infrastructure.JidoActionErrorJSON.encode_error(error, opts)
end

defimpl Jason.Encoder, for: Jido.Action.Error.ExecutionFailureError do
  def encode(error, opts), do: Firmowid.Infrastructure.JidoActionErrorJSON.encode_error(error, opts)
end

defimpl Jason.Encoder, for: Jido.Action.Error.TimeoutError do
  def encode(error, opts), do: Firmowid.Infrastructure.JidoActionErrorJSON.encode_error(error, opts)
end

defimpl Jason.Encoder, for: Jido.Action.Error.ConfigurationError do
  def encode(error, opts), do: Firmowid.Infrastructure.JidoActionErrorJSON.encode_error(error, opts)
end

defimpl Jason.Encoder, for: Jido.Action.Error.InternalError do
  def encode(error, opts), do: Firmowid.Infrastructure.JidoActionErrorJSON.encode_error(error, opts)
end

defimpl Jason.Encoder, for: Jido.Action.Error.Internal.UnknownError do
  def encode(error, opts), do: Firmowid.Infrastructure.JidoActionErrorJSON.encode_error(error, opts)
end
