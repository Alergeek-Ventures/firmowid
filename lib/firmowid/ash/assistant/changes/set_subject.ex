defmodule Firmowid.Ash.Assistant.Changes.SetSubject do
  @moduledoc "Stores an authorized subject as reference context without starting an assistant run."
  use Ash.Resource.Change

  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Core.User
  alias Firmowid.Ash.Finances
  alias Firmowid.Ash.Finances.Transaction
  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Timetracker.Project

  @impl true
  def change(changeset, _opts, context) do
    type = Ash.Changeset.get_argument(changeset, :subject_type)
    id = Ash.Changeset.get_argument(changeset, :subject_id)
    opts = [actor: context.actor, tenant: context.tenant]

    case read_subject(type, id, opts) do
      {:ok, subject} ->
        title = subject_title(subject)

        changeset
        |> Ash.Changeset.force_change_attribute(:subject, %{
          "type" => Atom.to_string(type),
          "id" => subject.id,
          "title" => title
        })
        |> Ash.Changeset.force_change_attribute(:title, String.slice(title || "", 0, 100))

      {:error, error} ->
        Ash.Changeset.add_error(changeset, error)
    end
  end

  defp read_subject(:transaction, id, opts),
    do: Finances.get_transaction(id, Keyword.put(opts, :load, [:counterparty_name]))

  defp read_subject(:sales_invoice, id, opts), do: Invoicing.get_sales_invoice(id, opts)
  defp read_subject(:cost_invoice, id, opts), do: Invoicing.get_cost_invoice(id, opts)

  defp read_subject(:employee, id, opts),
    do: Core.get_org_user(%{id: id}, Keyword.put(opts, :load, member: :display_name))

  defp read_subject(:project, id, opts), do: Project.get(id, opts)

  defp subject_title(%Transaction{} = transaction),
    do: transaction.remittance_information_unstructured || transaction.counterparty_name

  defp subject_title(%SalesInvoice{} = invoice), do: invoice.invoice_number
  defp subject_title(%CostInvoice{} = invoice), do: invoice.invoice_identifier
  defp subject_title(%User{} = employee), do: employee.member.display_name
  defp subject_title(%Project{} = project), do: project.name
end
