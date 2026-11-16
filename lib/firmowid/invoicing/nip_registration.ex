defmodule Firmowid.Invoicing.NipRegistration do
  @moduledoc """
  Checks a Polish counterparty's NIP in the public registers.

  The VAT white list (WL2) answers for VAT payers. A business outside the VAT
  register is looked up in REGON (GUS), which lists every company, sole
  proprietorship, foundation and association with its end date and a revoked
  NIP, so it tells a business that only does not pay VAT from one that is closed
  or never existed. CEIDG and KRS add nothing to that question: GUS takes sole
  proprietorships from CEIDG, and KRS cannot be searched by NIP.
  """

  alias Firmowid.Core.Nip
  alias Firmowid.Core.Services.VatApiClient
  alias Gusex.Types.Podmiot

  @type status :: :active | :exempt | :no_vat | :closed | :unknown | :unavailable

  # GUS allows 120 requests a minute per key, shared with CompanyRegister, which
  # makes at most 96; one search every 2.5 s keeps both under it.
  @gus_pause_ms 2_500

  @doc """
  Returns the NIP's status: an `:active` or `:exempt` VAT payer, a business
  outside VAT (`:no_vat`), a closed one or a revoked NIP (`:closed`), a NIP no
  register knows (`:unknown`), or `:unavailable` when a register does not answer
  or GUS is not configured.
  """
  @spec check(String.t()) :: status()
  def check(tax_id) do
    # A counterparty keeps its NIP as typed, e.g. "123-456-32-18".
    nip = Nip.normalize_digits(tax_id)

    case VatApiClient.fetch_status(nip) do
      {:ok, "C"} -> :active
      {:ok, "Z"} -> :exempt
      {:ok, code} when code in ["N", "B"] -> business_status(nip)
      {:ok, "X"} -> :unavailable
      {:error, _reason} -> :unavailable
    end
  end

  defp business_status(nip) do
    if Application.get_env(:gusex, :api_key) do
      Process.sleep(@gus_pause_ms)
      gus_status(Gusex.find_by_nip(nip))
    else
      :unavailable
    end
  end

  # GUS also returns local units (types LP and LF); legal entities (P) and
  # natural persons' businesses (F) are the ones that hold the NIP.
  defp gus_status({:ok, entities}) do
    businesses = Enum.filter(entities, &(&1."Typ" in ["P", "F"]))

    cond do
      businesses == [] -> :unknown
      Enum.any?(businesses, &operating?/1) -> :no_vat
      true -> :closed
    end
  end

  # Error 4: no entity has this NIP.
  defp gus_status({:error, %{ErrorCode: "4"}}), do: :unknown
  defp gus_status({:error, _reason}), do: :unavailable

  # StatusNip is "Uchylony" or "Unieważniony" for a revoked NIP.
  defp operating?(%Podmiot{DataZakonczeniaDzialalnosci: ended, StatusNip: nip_status}),
    do: is_nil(ended) and nip_status in [nil, ""]
end
