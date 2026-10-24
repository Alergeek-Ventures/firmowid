defmodule Firmowid.ErrorKind do
  @moduledoc """
  Classifies error-like values into stable, non-sensitive categories.
  """

  @doc "Returns a stable, non-sensitive category for an error-like value."
  @spec classify(term()) :: String.t()
  def classify(value), do: classify(value, 0)

  # Bound both depth and fan-out; never traverse changesets, records or messages.
  defp classify(_value, depth) when depth >= 4, do: "truncated"

  defp classify(%module{errors: [_ | _] = errors}, depth)
       when module in [Ash.Error.Invalid, Ash.Error.Unknown, Ash.Error.Forbidden, Ash.Error.Framework] do
    kinds =
      errors
      |> Enum.take(8)
      |> Enum.map(&classify(&1, depth + 1))
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.join(",")

    Atom.to_string(module) <> ":" <> kinds
  end

  defp classify(%Req.TransportError{reason: reason}, _depth), do: "Elixir.Req.TransportError:" <> transport_kind(reason)

  defp classify(%Postgrex.Error{postgres: %{pg_code: code}}, _depth) when is_binary(code) do
    if Regex.match?(~r/\A[0-9A-Z]{5}\z/, code) do
      category =
        %{
          "23502" => :not_null,
          "23503" => :foreign_key,
          "23505" => :unique,
          "23514" => :check,
          "23P01" => :exclusion
        }[code]

      "Elixir.Postgrex.Error:sqlstate=" <> code <> constraint_suffix(category)
    else
      "Elixir.Postgrex.Error"
    end
  end

  defp classify(%Ecto.ConstraintError{type: type}, _depth), do: "Elixir.Ecto.ConstraintError" <> constraint_suffix(type)

  defp classify(%Ash.Error.Changes.InvalidAttribute{private_vars: vars}, _depth),
    do: "Elixir.Ash.Error.Changes.InvalidAttribute" <> constraint_suffix(vars[:constraint_type])

  defp classify(%{__struct__: module}, _depth) when is_atom(module), do: Atom.to_string(module)

  defp classify({kind, nested}, depth) when is_atom(kind), do: Atom.to_string(kind) <> ":" <> classify(nested, depth + 1)

  defp classify(nil, _depth), do: "null"
  defp classify(value, _depth) when is_boolean(value), do: "boolean"
  defp classify(value, _depth) when is_atom(value), do: Atom.to_string(value)
  defp classify(value, _depth) when is_binary(value), do: "binary"
  defp classify(value, _depth) when is_list(value), do: "list"
  defp classify(value, _depth) when is_map(value), do: "map"
  defp classify(value, _depth) when is_tuple(value), do: "tuple"
  defp classify(value, _depth) when is_integer(value), do: "integer"
  defp classify(value, _depth) when is_float(value), do: "float"
  defp classify(value, _depth) when is_pid(value), do: "pid"
  defp classify(value, _depth) when is_reference(value), do: "reference"
  defp classify(value, _depth) when is_function(value), do: "function"
  defp classify(_value, _depth), do: "other"

  # Req 0.7 delegates transport reasons to Mint 1.11. TLS tuples contain
  # arbitrary peer text: classify their tag, never stringify their contents.
  defp transport_kind(reason) when reason in [:timeout, :etimedout], do: "timeout"
  defp transport_kind(reason) when reason in [:nxdomain, :eai_again], do: "dns"
  defp transport_kind(reason) when reason in [:closed, :econnreset], do: "closed"
  defp transport_kind(:econnrefused), do: "refused"
  defp transport_kind(:protocol_not_negotiated), do: "tls"
  defp transport_kind({tag, _}) when tag in [:tls_alert, :bad_alpn_protocol, :bad_cert], do: "tls"
  defp transport_kind(_reason), do: "other"

  defp constraint_suffix(type) when type in [:unique, :foreign_key, :check, :exclusion, :not_null],
    do: ":constraint=" <> Atom.to_string(type)

  defp constraint_suffix(_type), do: ""
end
