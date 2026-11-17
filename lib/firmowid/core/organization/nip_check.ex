defmodule Firmowid.Core.Organization.NipCheck do
  @moduledoc """
  What the VAT white list and CEIDG last said about the organization's own NIP
  (`NipRegistration`, run by `VatIdCheckWorker`), and how the company details
  contradict it.
  """
  use Spark.Dsl.Fragment, of: Ash.Resource, notifiers: [Ash.Notifier.PubSub]

  require Ash.Expr

  @type mismatch :: :closed | :unknown | :not_vat_payer_in_register | :vat_payer_in_register

  actions do
    update :record_nip_check do
      description "Record what the VAT white list and CEIDG last said about the organization's NIP."
      accept [:nip_status, :nip_checked_at]
      require_atomic? false

      # A NIP saved while the registers answered has a check of its own, so an answer
      # about the NIP the caller read is stale and fails with `StaleRecord`.
      change fn changeset, _context ->
        Ash.Changeset.filter(changeset, expr(nip == ^changeset.data.nip))
      end
    end
  end

  pub_sub do
    module FirmowidWeb.Core.Endpoint
    prefix "organization"

    publish :record_nip_check, ["nip_checked", :id]
  end

  attributes do
    attribute :nip_status, :atom,
      public?: true,
      constraints: [one_of: [:active, :exempt, :no_vat, :closed, :unknown]],
      description: "What the VAT white list and CEIDG last said about the NIP; nil until checked."

    attribute :nip_checked_at, :utc_datetime_usec, public?: true
  end

  @doc """
  Tells how the company details contradict the registers' last answer about the
  NIP: the business is deregistered (`:closed`), no register knows the NIP
  (`:unknown`), or the company is set as a VAT payer while the white list does
  not list it as an active one (`:not_vat_payer_in_register`), or the other way
  round (`:vat_payer_in_register`). Nil when they agree or the NIP is not checked yet.
  """
  @spec mismatch(Firmowid.Core.Organization.t()) :: mismatch() | nil
  def mismatch(%{nip_status: status}) when status in [:closed, :unknown], do: status

  def mismatch(%{is_vat_payer: true, nip_status: status}) when status in [:exempt, :no_vat],
    do: :not_vat_payer_in_register

  def mismatch(%{is_vat_payer: false, nip_status: :active}), do: :vat_payer_in_register
  def mismatch(_organization), do: nil
end
