defmodule Firmowid.ParadeDBFieldName do
  @moduledoc """
  Postgrex extension for ParadeDB's `fieldname` type.

  Handles encoding/decoding of field name references used by ParadeDB
  search indexes.
  """
  @behaviour Postgrex.Extension

  import Postgrex.BinaryUtils, warn: false

  @impl true
  def init(_opts), do: nil

  @impl true
  def matching(_state), do: [type: "fieldname"]

  @impl true
  def format(_state), do: :text

  @impl true
  def encode(_state) do
    quote do
      bin when is_binary(bin) -> [<<byte_size(bin)::int32()>> | bin]
    end
  end

  @impl true
  def decode(_state) do
    quote do
      <<len::int32(), bin::binary-size(len)>> -> bin
    end
  end
end
