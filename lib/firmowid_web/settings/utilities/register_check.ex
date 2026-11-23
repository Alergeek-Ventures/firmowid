defmodule FirmowidWeb.Settings.Utilities.RegisterCheck do
  @moduledoc """
  Describes what the public registers last said about the organization's NIP,
  for the company details and for the inbox item raised when the company
  details contradict it (`Organization.NipCheck.mismatch/1`).
  """

  use Gettext, backend: Firmowid.Gettext

  alias Firmowid.Core.Organization
  alias Firmowid.Core.Organization.NipCheck

  @typedoc """
  `field` names the company detail the contradiction concerns, so the message
  sits under it; `danger?` marks a register answer that is itself a problem.
  """
  @type status :: %{
          result: atom(),
          label: String.t(),
          meta: String.t() | nil,
          danger?: boolean(),
          problem: String.t() | nil,
          field: :nip | :is_vat_payer | nil
        }

  @doc "The registers' answer, when it was checked and the contradiction, if any."
  @spec status(Organization.t()) :: status()
  def status(%Organization{nip_status: nil}),
    do: %{
      result: :pending,
      label: pgettext("NIP status", "Checking in registers"),
      meta: nil,
      danger?: false,
      problem: nil,
      field: nil
    }

  def status(%Organization{nip_status: nip_status, nip_checked_at: checked_at} = organization) do
    %{
      result: nip_status,
      label: label(nip_status),
      meta:
        gettext("Checked in the registers on %{date}",
          date: Calendar.strftime(checked_at, "%d.%m.%Y")
        ),
      danger?: nip_status == :closed,
      problem: problem(organization),
      field: field(NipCheck.mismatch(organization))
    }
  end

  @doc "How the company details contradict the registers, nil when they agree or are not checked yet."
  @spec problem(Organization.t()) :: String.t() | nil
  def problem(organization) do
    case {NipCheck.mismatch(organization), organization.nip_status, organization.nip_registers} do
      {nil, _status, _registers} ->
        nil

      {:closed, _status, %{krs: :struck_off}} ->
        gettext("KRS shows the company with this NIP as struck off. Check that the NIP is right.")

      {:closed, _status, _registers} ->
        gettext("CEIDG shows the business with this NIP as deregistered. Check that the NIP is right.")

      {:not_vat_payer_in_register, :exempt, _registers} ->
        gettext("The VAT white list shows the company as VAT-exempt, but here it is set as a VAT payer.")

      {:not_vat_payer_in_register, status, _registers} when status in [:no_vat, :unconfirmed] ->
        gettext("The VAT white list does not show the company as a VAT payer, but here it is set as one.")

      {:vat_payer_in_register, :active, _registers} ->
        gettext("The VAT white list shows the company as an active VAT payer, but here it is not set as one.")
    end
  end

  defp field(:closed), do: :nip

  defp field(mismatch) when mismatch in [:not_vat_payer_in_register, :vat_payer_in_register], do: :is_vat_payer

  defp field(nil), do: nil

  defp label(:active), do: pgettext("NIP status", "Active VAT payer")
  defp label(:exempt), do: pgettext("NIP status", "VAT-exempt")
  defp label(:no_vat), do: pgettext("NIP status", "Not a VAT payer")
  defp label(:closed), do: pgettext("NIP status", "Business closed")
  defp label(:unconfirmed), do: pgettext("NIP status", "Not confirmed in registers")
end
