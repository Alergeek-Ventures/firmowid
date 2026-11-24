defmodule Firmowid.Invoicing.Changes.PayOnIssue do
  @moduledoc """
  Keeps an invoice that is paid when issued (the resource's `is_paid_on_issue`) free of a payment
  term: it has no due date, and its payment date (the resource's `payment_date`) cannot be after
  its issue date. The payment itself is expected by `ExpectPayment` once the invoice is issued.

  An advance invoice is paid on its sale date, so it keeps no `paid_on`.

  Runs after the issue date is set.
  """
  use Ash.Resource.Change
  use Gettext, backend: Firmowid.Gettext

  @doc "Clears the due date of an invoice paid on issue and checks its payment date."
  @spec change(Ash.Changeset.t(), keyword(), Ash.Resource.Change.Context.t()) :: Ash.Changeset.t()
  @impl true
  def change(changeset, _opts, context) do
    kind = Ash.Changeset.get_attribute(changeset, :ksef_invoice_kind)

    changeset =
      if kind == :advance,
        do: Ash.Changeset.force_change_attribute(changeset, :paid_on, nil),
        else: changeset

    refs = %{
      ksef_invoice_kind: kind,
      sale_date: Ash.Changeset.get_attribute(changeset, :sale_date),
      paid_on: Ash.Changeset.get_attribute(changeset, :paid_on)
    }

    if calculate(changeset, :is_paid_on_issue, refs, context),
      do: pay_on_issue(changeset, kind, calculate(changeset, :payment_date, refs, context)),
      else: changeset
  end

  defp calculate(changeset, calculation, refs, context) do
    opts = context |> Ash.Context.to_opts() |> Keyword.put(:refs, refs)
    Ash.calculate!(changeset.resource, calculation, opts)
  end

  defp pay_on_issue(changeset, kind, payment_date) do
    issue_date = Ash.Changeset.get_attribute(changeset, :issue_date)
    changeset = Ash.Changeset.force_change_attribute(changeset, :due_date, nil)

    # The invoice states the payment as made, so it cannot be dated after the invoice itself.
    if payment_date && issue_date && Date.after?(payment_date, issue_date) do
      Ash.Changeset.add_error(changeset,
        field: if(kind == :advance, do: :sale_date, else: :paid_on),
        message: gettext_noop("The payment date cannot be after the issue date.")
      )
    else
      changeset
    end
  end
end
