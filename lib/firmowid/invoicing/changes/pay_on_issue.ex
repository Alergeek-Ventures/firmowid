defmodule Firmowid.Invoicing.Changes.PayOnIssue do
  @moduledoc """
  Keeps an invoice that is paid when issued (the resource's `is_paid_on_issue`) free of payment
  expectations: it is due on its payment date (the resource's `payment_date`), which cannot be
  after its issue date, and awaits no transaction. A draft revised so it is no longer paid on
  issue awaits a transaction again.

  An advance invoice is paid on its sale date, so it keeps no `paid_on`.

  Runs after the issue date is set.
  """
  use Ash.Resource.Change
  use Gettext, backend: Firmowid.Gettext

  @doc "Sets the due date and payment matching of an invoice from whether it is paid on issue."
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

    saved_refs = Map.take(changeset.data, [:ksef_invoice_kind, :sale_date, :paid_on])

    cond do
      calculate(changeset, :is_paid_on_issue, refs, context) ->
        pay_on_issue(changeset, kind, calculate(changeset, :payment_date, refs, context))

      calculate(changeset, :is_paid_on_issue, saved_refs, context) ->
        Ash.Changeset.force_change_attribute(changeset, :skip_invoicing, false)

      true ->
        changeset
    end
  end

  defp calculate(changeset, calculation, refs, context) do
    opts = context |> Ash.Context.to_opts() |> Keyword.put(:refs, refs)
    Ash.calculate!(changeset.resource, calculation, opts)
  end

  defp pay_on_issue(changeset, kind, payment_date) do
    issue_date = Ash.Changeset.get_attribute(changeset, :issue_date)

    changeset =
      Ash.Changeset.force_change_attributes(changeset,
        due_date: payment_date,
        skip_invoicing: true
      )

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
