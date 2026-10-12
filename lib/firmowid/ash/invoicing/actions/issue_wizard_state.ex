defmodule Firmowid.Ash.Invoicing.Actions.IssueWizardState do
  @moduledoc "Adapts ephemeral browser wizard fields to shared invoice preview and issuance actions."
  use Ash.Resource.Actions.Implementation

  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Invoicing.WizardState

  require Logger

  @invoice_fields [
    :counterparty_id,
    :buyer_type,
    :buyer_id,
    :buyer_full_name,
    :buyer_given_name,
    :buyer_surname,
    :buyer_pesel,
    :buyer_display_name,
    :buyer_address,
    :buyer_country,
    :buyer_email,
    :buyer_phone,
    :buyer_description,
    :invoice_type,
    :is_reverse_charge,
    :currency,
    :seller_account_number,
    :sale_date,
    :due_date,
    :payment_method,
    :vat_exemption_type,
    :vat_exemption_basis,
    :invoice_note,
    :internal_note
  ]

  @impl true
  def run(input, action_opts, context) do
    opts = Ash.Context.to_opts(context)

    with {:ok, state} <- Ash.get(WizardState, input.arguments.state_id, opts),
         {:ok, state} <- Ash.load(state, [:items], opts) do
      attrs = invoice_attributes(state, input.arguments)

      if action_opts[:preview?] do
        Invoicing.preview_sales_invoice(%{input: attrs}, opts)
      else
        result =
          if input.arguments.draft do
            Invoicing.save_sales_invoice_draft(%{input: attrs}, opts)
          else
            Invoicing.issue_sales_invoice(
              %{input: attrs, submit_to_ksef: input.arguments.submit_to_ksef},
              opts
            )
          end

        with {:ok, invoice} <- result do
          discard_state(state, opts)
          {:ok, invoice}
        end
      end
    end
  end

  # The invoice is already committed. Failing here would invite issuing it a second time.
  defp discard_state(state, opts) do
    case WizardState.destroy(state, opts) do
      :ok ->
        :ok

      {:error, error} ->
        Logger.warning("Issued invoice left its browser wizard state behind",
          organization_id: state.organization_id,
          error_kind: Firmowid.ErrorKind.classify(error)
        )
    end
  end

  defp invoice_attributes(state, arguments) do
    items =
      state.items
      |> Enum.sort_by(& &1.index)
      |> Enum.with_index()
      |> Enum.map(fn {item, index} ->
        item
        |> Map.take([:name, :quantity, :unit, :unit_price, :vat_rate])
        |> Map.put(:index, index)
      end)

    state
    |> Map.take(@invoice_fields)
    |> Map.put(:sales_invoice_items, items)
    |> Map.put(:invoice_number, arguments.invoice_number)
    |> Map.put(:should_send_emails, arguments.should_send_emails)
  end
end
