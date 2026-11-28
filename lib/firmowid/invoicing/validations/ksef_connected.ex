defmodule Firmowid.Invoicing.Validations.KsefConnected do
  @moduledoc """
  Ash validation that the organization is connected to KSeF, for what issues invoices on its
  own, such as the invoices of Stripe payments.
  """
  use Ash.Resource.Validation
  use Gettext, backend: Firmowid.Gettext

  alias Firmowid.Ksef
  alias Firmowid.Scope

  @impl true
  def validate(changeset, _opts, context) do
    if Ksef.connected?(%Scope{actor: context.actor, tenant: changeset.tenant}) do
      :ok
    else
      {:error, field: :base, message: gettext_noop("Connect the company to KSeF first.")}
    end
  end
end
