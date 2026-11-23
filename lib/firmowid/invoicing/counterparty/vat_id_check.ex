defmodule Firmowid.Invoicing.Counterparty.VatIdCheck do
  @moduledoc """
  What the last check of a counterparty's EU VAT number (`EuVatReview`) or NIP
  (`NipRegistration`), run by `VatIdCheckWorker`, found.
  """
  use Spark.Dsl.Fragment, of: Ash.Resource, notifiers: [Ash.Notifier.PubSub]

  @statuses [:active, :inactive, :invalid, :exempt, :no_vat, :closed, :unconfirmed]

  @doc "Results a check can record in `vat_id_status`."
  @spec statuses() :: [atom()]
  def statuses, do: @statuses

  actions do
    update :record_vat_id_check do
      description "Record the result of the periodic EU VAT number or NIP check."
      accept [:vat_id_status, :vat_id_checked_at, :nip_registers]
    end
  end

  pub_sub do
    module FirmowidWeb.Core.Endpoint
    prefix "counterparty"

    publish :record_vat_id_check, ["vat_id_checked", :id]
  end

  attributes do
    attribute :vat_id_status, :atom,
      public?: true,
      constraints: [one_of: @statuses],
      description: """
      Last check of the EU VAT number (`EuVatReview`) or NIP (`NipRegistration`).
      `unconfirmed` means no register that can be searched by NIP lists it, e.g. a
      KRS company outside VAT; it does not mean the counterparty does not exist.
      """

    attribute :vat_id_checked_at, :utc_datetime_usec, public?: true

    attribute :nip_registers, Firmowid.Core.NipRegisters,
      public?: true,
      description: "What each register said in the last NIP check; nil for other tax IDs or until checked."
  end
end
