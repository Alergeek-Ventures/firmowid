defmodule Firmowid.Invoicing.Changes.PayOnIssue do
  @moduledoc """
  Keeps an invoice that is paid when issued (the resource's `is_paid_on_issue`) free of a payment
  term: it is due on the payment date, its `sale_date`, which cannot be after its issue date.
  The payment itself is expected by `ExpectPayment` once the invoice is issued.

  Runs after the issue date is set.
  """
  use Ash.Resource.Change
  use Gettext, backend: Firmowid.Gettext

  @doc "Sets the due date of an invoice paid on issue to its payment date."
  @spec change(Ash.Changeset.t(), keyword(), Ash.Resource.Change.Context.t()) :: Ash.Changeset.t()
  @impl true
  def change(changeset, _opts, context) do
    kind = Ash.Changeset.get_attribute(changeset, :ksef_invoice_kind)
    opts = context |> Ash.Context.to_opts() |> Keyword.put(:refs, %{ksef_invoice_kind: kind})

    if Ash.calculate!(changeset.resource, :is_paid_on_issue, opts),
      do: pay_on_issue(changeset),
      else: changeset
  end

  defp pay_on_issue(changeset) do
    payment_date = Ash.Changeset.get_attribute(changeset, :sale_date)
    issue_date = Ash.Changeset.get_attribute(changeset, :issue_date)
    changeset = Ash.Changeset.force_change_attribute(changeset, :due_date, payment_date)

    # The invoice states the payment as made, so it cannot be dated after the invoice itself.
    if payment_date && issue_date && Date.after?(payment_date, issue_date) do
      Ash.Changeset.add_error(changeset,
        field: :sale_date,
        message: gettext_noop("The payment date of an advance invoice cannot be after its issue date.")
      )
    else
      changeset
    end
  end
end
