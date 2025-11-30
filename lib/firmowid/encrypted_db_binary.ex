defmodule Firmowid.Encrypted.Binary do
  @moduledoc false
  use Cloak.Ecto.Binary, vault: Firmowid.Vault
end
