defmodule Firmowid.Invoicing.NipRegistration do
  @moduledoc """
  Checks a Polish NIP in the public registers and keeps each register's answer
  (`Firmowid.Core.NipRegisters`).

  The VAT white list (WL2) answers for VAT payers. A NIP outside the VAT register
  is looked up in KRS, then in CEIDG, which lists sole proprietorships. KRS cannot be
  searched by NIP: the number comes from the counterparty, or from the white list's
  search for a NIP it knows from an earlier VAT registration. Without a number, a
  company or foundation that never registered for VAT is in no register we can ask:
  such a NIP is `:unconfirmed`, never treated as nonexistent.
  """

  alias Firmowid.Core.Nip
  alias Firmowid.Core.NipRegisters
  alias Firmowid.Core.Services.CeidgApiClient
  alias Firmowid.Core.Services.KrsApiClient
  alias Firmowid.Core.Services.VatApiClient

  @type status :: :active | :exempt | :no_vat | :closed | :unconfirmed

  @doc """
  Returns the NIP's status with each register's answer: an `:active` or `:exempt`
  VAT payer, a business outside VAT (`:no_vat`), one struck off KRS or with only
  deregistered businesses in CEIDG (`:closed`), or a NIP no register we can ask
  confirms (`:unconfirmed`). `:unavailable` when a register does not answer or
  CEIDG is not configured. `krs` is the KRS number the counterparty gave, if any.
  """
  @spec check(String.t(), String.t() | nil) :: {status(), NipRegisters.t()} | :unavailable
  def check(tax_id, krs \\ nil) do
    # A counterparty keeps its NIP as typed, e.g. "123-456-32-18".
    nip = Nip.normalize_digits(tax_id)

    with {:ok, white_list} <- white_list(nip),
         {:ok, registers} <- look_further(nip, %NipRegisters{white_list: white_list}, krs) do
      {status(registers), registers}
    else
      {:error, _reason} -> :unavailable
    end
  end

  defp white_list(nip) do
    case VatApiClient.fetch_status(nip) do
      {:ok, "C"} -> {:ok, :active}
      {:ok, "Z"} -> {:ok, :exempt}
      {:ok, "N"} -> {:ok, :not_registered}
      {:ok, "B"} -> {:ok, :absent}
      {:ok, "I"} -> {:ok, :invalid}
      # "X": the service is inactive.
      {:ok, code} -> {:error, {:white_list_status, code}}
      {:error, _reason} = error -> error
    end
  end

  defp look_further(nip, %{white_list: white_list} = registers, krs) when white_list in [:not_registered, :absent] do
    with {:ok, registers} <- krs(nip, registers, krs) do
      # A KRS entity is no sole proprietorship, so CEIDG has nothing to add.
      if registers.krs in [:entered, :struck_off],
        do: {:ok, registers},
        else: ceidg(nip, registers)
    end
  end

  # A VAT payer is confirmed by the white list itself; an invalid NIP has nothing to look up.
  defp look_further(_nip, registers, _krs), do: {:ok, registers}

  defp krs(nip, registers, number) when is_binary(number), do: krs_lookup(nip, registers, number)

  # The white list's search keeps subjects removed from the VAT register, with their KRS
  # number; its daily limit is low, so it is asked only for such NIPs.
  defp krs(nip, %{white_list: :not_registered} = registers, nil) do
    case VatApiClient.fetch_by_nip(nip) do
      {:ok, %{"result" => %{"subject" => %{"krs" => number}}}} when number not in [nil, ""] ->
        krs_lookup(nip, registers, number)

      {:ok, %{"result" => _no_krs_number}} ->
        {:ok, registers}

      {:error, _reason} = error ->
        error
    end
  end

  defp krs(_nip, registers, nil), do: {:ok, registers}

  defp krs_lookup(nip, registers, number) do
    with {:ok, extract} <- KrsApiClient.fetch_current(number),
         {:ok, result} <- krs_result(extract, nip, number) do
      {:ok, %{registers | krs_number: number, krs: result}}
    end
  end

  # A struck-off entry's current extract is empty, so its NIP comes from the full one;
  # a mistyped number must not mark the company as struck off.
  defp krs_result(:struck_off, nip, number) do
    with {:ok, nips} <- KrsApiClient.fetch_past_nips(number),
         do: {:ok, if(nip in nips, do: :struck_off, else: :other_nip)}
  end

  defp krs_result(:not_found, _nip, _number), do: {:ok, :not_found}

  defp krs_result(data, nip, _number) do
    if get_in(data, ["dzial1", "danePodmiotu", "identyfikatory", "nip"]) == nip,
      do: {:ok, :entered},
      else: {:ok, :other_nip}
  end

  defp ceidg(nip, registers) do
    case CeidgApiClient.fetch_businesses(nip) do
      {:ok, []} ->
        {:ok, %{registers | ceidg: :absent}}

      # A NIP may hold several businesses over the years; one not deregistered keeps it in business.
      {:ok, businesses} ->
        state =
          if Enum.all?(businesses, &(&1["status"] == "WYKRESLONY")),
            do: :deregistered,
            else: :listed

        {:ok, %{registers | ceidg: state}}

      {:error, _reason} = error ->
        error
    end
  end

  defp status(%{white_list: :active}), do: :active
  defp status(%{white_list: :exempt}), do: :exempt
  defp status(%{krs: :entered}), do: :no_vat
  defp status(%{ceidg: :listed}), do: :no_vat
  defp status(%{krs: :struck_off}), do: :closed
  defp status(%{ceidg: :deregistered}), do: :closed
  # The white list knows the NIP from an earlier VAT registration, so it exists.
  defp status(%{white_list: :not_registered}), do: :no_vat
  defp status(_registers), do: :unconfirmed
end
