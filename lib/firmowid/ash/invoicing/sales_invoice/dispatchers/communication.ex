defmodule Firmowid.Ash.Invoicing.SalesInvoice.Dispatchers.Communication do
  @moduledoc """
  Dispatches communication work for sales invoice events.
  """

  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Invoicing.SalesInvoice.Dispatchers.Email
  alias Firmowid.Ash.Scope

  @doc """
  Dispatches work for a sales invoice event across communication channels.
  """
  @spec dispatch(SalesInvoice.t(), :ksef_confirmed | :overdue_reminder, Scope.t()) ::
          {:ok, :dispatched | :skipped} | {:error, term()}
  def dispatch(%SalesInvoice{} = invoice, event, scope) when event in [:ksef_confirmed, :overdue_reminder] do
    Email.dispatch(invoice, event, scope)
    # later add other channels like Slack
  end
end
