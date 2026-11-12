defmodule Firmowid.Invoicing.Changes.PayOnIssue do
  @moduledoc """
  Keeps an invoice that is paid when issued (the resource's `is_paid_on_issue`) free of payment
  expectations: it is due on the payment date, its `sale_date`, which cannot be after its issue
  date, and awaits no transaction. A draft revised away from such a kind awaits a transaction again.

  Runs after the issue date is set.
  """
  use Ash.Resource.Change
  use Gettext, backend: Firmowid.Gettext

  @doc "Sets the due date and payment matching of an invoice from whether it is paid on issue."
  @spec change(Ash.Changeset.t(), keyword(), Ash.Resource.Change.Context.t()) :: Ash.Changeset.t()
  @impl true
  def change(changeset, _opts, context) do
    cond do
      paid_on_issue?(
        changeset,
        Ash.Changeset.get_attribute(changeset, :ksef_invoice_kind),
        context
      ) ->
        pay_on_issue(changeset)

      paid_on_issue?(changeset, changeset.data.ksef_invoice_kind, context) ->
        Ash.Changeset.force_change_attribute(changeset, :skip_invoicing, false)

      true ->
        changeset
    end
  end

  defp paid_on_issue?(changeset, kind, context) do
    opts = context |> Ash.Context.to_opts() |> Keyword.put(:refs, %{ksef_invoice_kind: kind})
    Ash.calculate!(changeset.resource, :is_paid_on_issue, opts)
  end

  defp pay_on_issue(changeset) do
    payment_date = Ash.Changeset.get_attribute(changeset, :sale_date)
    issue_date = Ash.Changeset.get_attribute(changeset, :issue_date)

    changeset =
      Ash.Changeset.force_change_attributes(changeset,
        due_date: payment_date,
        skip_invoicing: true
      )

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
