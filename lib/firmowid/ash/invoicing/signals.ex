defmodule Firmowid.Ash.Invoicing.Signals do
  @moduledoc """
  Signals emitted by the Invoicing domain for other resources to react to.
  """

  use Ash.Signals

  signals do
    signal :cost_invoice_created do
      description "A cost invoice was imported from KSeF, an inbound email or an uploaded document."
      argument :cost_invoice_id, :uuid, allow_nil?: false
      argument :organization_id, :uuid, allow_nil?: false
    end
  end
end
