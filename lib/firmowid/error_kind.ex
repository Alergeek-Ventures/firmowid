defmodule Firmowid.ErrorKind do
  @moduledoc """
  Classifies error-like values into stable, non-sensitive categories.
  """

  @doc "Returns a stable, non-sensitive category for an error-like value."
  @spec classify(term()) :: String.t()
  def classify(%{__struct__: module}) when is_atom(module), do: Atom.to_string(module)

  def classify({kind, nested}) when is_atom(kind), do: Atom.to_string(kind) <> ":" <> classify(nested)

  def classify(nil), do: "null"
  def classify(value) when is_boolean(value), do: "boolean"
  def classify(value) when is_atom(value), do: Atom.to_string(value)
  def classify(value) when is_binary(value), do: "binary"
  def classify(value) when is_list(value), do: "list"
  def classify(value) when is_map(value), do: "map"
  def classify(value) when is_tuple(value), do: "tuple"
  def classify(value) when is_integer(value), do: "integer"
  def classify(value) when is_float(value), do: "float"
  def classify(value) when is_pid(value), do: "pid"
  def classify(value) when is_reference(value), do: "reference"
  def classify(value) when is_function(value), do: "function"
  def classify(_value), do: "other"
end
