defmodule Firmowid.Invoicing.NipRegistration do
  @moduledoc """
  Checks a Polish counterparty's NIP in the public registers.

  The VAT white list (WL2) answers for VAT payers. A NIP outside the VAT register
  is looked up in CEIDG, which lists sole proprietorships with their status, so it
  tells one that only does not pay VAT from one that was deregistered. A NIP
  neither register knows is most likely a typo; KRS cannot be searched by NIP.
  """

  alias Firmowid.Core.Nip
  alias Firmowid.Core.Services.CeidgApiClient
  alias Firmowid.Core.Services.VatApiClient

  @type status :: :active | :exempt | :no_vat | :closed | :unknown | :unavailable

  @doc """
  Returns the NIP's status: an `:active` or `:exempt` VAT payer, a business
  outside VAT (`:no_vat`), a deregistered sole proprietorship (`:closed`), a NIP
  no register knows (`:unknown`), or `:unavailable` when a register does not
  answer or CEIDG is not configured.
  """
  @spec check(String.t()) :: status()
  def check(tax_id) do
    # A counterparty keeps its NIP as typed, e.g. "123-456-32-18".
    nip = Nip.normalize_digits(tax_id)

    case VatApiClient.fetch_status(nip) do
      {:ok, "C"} -> :active
      {:ok, "Z"} -> :exempt
      {:ok, code} when code in ["N", "B"] -> ceidg_status(nip, code)
      # A NIP with a wrong check digit, which no register can know.
      {:ok, "I"} -> :unknown
      {:ok, "X"} -> :unavailable
      {:error, _reason} -> :unavailable
    end
  end

  defp ceidg_status(nip, white_list_code) do
    case CeidgApiClient.fetch_businesses(nip) do
      # "N" is a NIP the white list knows, deregistered from VAT or refused, so it exists.
      {:ok, []} when white_list_code == "N" ->
        :no_vat

      {:ok, []} ->
        :unknown

      {:ok, businesses} ->
        if Enum.all?(businesses, &(&1["status"] == "WYKRESLONY")), do: :closed, else: :no_vat

      {:error, _reason} ->
        :unavailable
    end
  end
end
