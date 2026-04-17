defmodule Firmowid.Ash.Invoicing.Utilities.SafeTimestamp do
  @moduledoc """
  Shared timestamp helpers with a deterministic fallback.

  `safe_timestamp/1` prefers `locked_at`, then `inserted_at`, and falls back to
  the Unix epoch when neither timestamp is available.
  """

  @fallback ~U[1970-01-01 00:00:00Z]

  @doc """
  Returns a record timestamp with fallback to epoch.
  """
  @spec safe_timestamp(map()) :: DateTime.t()
  def safe_timestamp(record) do
    case {record.locked_at, record.inserted_at} do
      {%DateTime{} = ts, _} -> ts
      {_, %DateTime{} = ts} -> ts
      _ -> @fallback
    end
  end

  @doc """
  Safely checks whether record timestamp is after the reference.
  """
  @spec safe_after?(map(), DateTime.t()) :: boolean()
  def safe_after?(record, %DateTime{} = reference) do
    DateTime.after?(safe_timestamp(record), reference)
  end
end
