defmodule Firmowid.Ash.Ksef.Validations.ValidateKsefToken do
  @moduledoc """
  Validates the format of a KSeF token and ensures the embedded NIP
  matches the current organization's NIP.
  """
  use Ash.Resource.Validation

  alias Firmowid.Ash.Core

  @impl true
  def validate(changeset, _opts, _context) do
    token = Ash.Changeset.get_argument(changeset, :ksef_token)

    with {:ok, token_nip} <- extract_nip(token),
         organization = Core.get_organization!(changeset.tenant),
         :ok <- validate_nip(token_nip, organization.nip) do
      :ok
    else
      {:error, :invalid_token_format} ->
        {:error, field: :ksef_token, message: "Nieprawidłowy format tokenu KSeF."}

      {:error, :nip_mismatch} ->
        {:error, field: :ksef_token, message: "NIP w tokenie nie zgadza się z NIP organizacji."}
    end
  end

  defp extract_nip(token) do
    case String.split(token, "|") do
      [_id, "nip-" <> nip, _hash] when byte_size(nip) > 0 -> {:ok, nip}
      _ -> {:error, :invalid_token_format}
    end
  end

  defp validate_nip(token_nip, org_nip) do
    normalized_token = String.replace(token_nip, ~r/\D/, "")
    normalized_org = String.replace(org_nip || "", ~r/\D/, "")

    if normalized_token == normalized_org, do: :ok, else: {:error, :nip_mismatch}
  end
end
