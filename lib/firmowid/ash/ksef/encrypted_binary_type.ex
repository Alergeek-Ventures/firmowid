defmodule Firmowid.Ash.Ksef.EncryptedBinaryType do
  @moduledoc """
  Ash type wrapper for `Firmowid.Encrypted.Binary` (Cloak Ecto type).

  Delegates all storage/casting operations to the underlying Ecto type,
  allowing it to be used as an Ash resource attribute.
  """

  use Ash.Type

  @ecto_type Firmowid.Encrypted.Binary

  @impl Ash.Type
  def storage_type(_constraints), do: :binary

  @impl Ash.Type
  def cast_input(nil, _constraints), do: {:ok, nil}

  def cast_input(value, _constraints) do
    Ecto.Type.cast(@ecto_type, value)
  end

  @impl Ash.Type
  def cast_stored(nil, _constraints), do: {:ok, nil}

  def cast_stored(value, _constraints) do
    Ecto.Type.load(@ecto_type, value)
  end

  @impl Ash.Type
  def dump_to_native(nil, _constraints), do: {:ok, nil}

  def dump_to_native(value, _constraints) do
    Ecto.Type.dump(@ecto_type, value)
  end

  @impl Ash.Type
  def describe(_constraints), do: "an encrypted binary (Cloak AES-256-GCM)"
end
