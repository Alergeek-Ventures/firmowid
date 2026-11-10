defmodule FirmowidUI.Invoicing.Issuance do
  @moduledoc """
  User-confirmed issuance of a previewed invoice or correction, with the asynchronous KSeF
  lifecycle. The MCP confirmation widget and the assistant's invoice card hold one of these and
  render it with `FirmowidUI.Invoicing.Components.Issuance`; each interface supplies its own
  scope, action context and shell.

  `confirmation_id` becomes the issued document's ID, so confirming the same preview twice, or
  reopening it after issuance, finds the issued document instead of issuing another one.
  """
  use Gettext, backend: Firmowid.Gettext

  alias AshPhoenix.FormData.Error
  alias Firmowid.Core
  alias Firmowid.Invoicing
  alias Firmowid.Invoicing.FailureReporter
  alias Firmowid.Invoicing.SalesInvoice
  alias Firmowid.Invoicing.SalesInvoice.Preview
  alias Firmowid.Ksef
  alias Firmowid.Ksef.SubmissionInfo
  alias Firmowid.Scope
  alias FirmowidUI.Components.Inputs

  @invoice_loads [
    :buyer_id_type,
    :corrected_invoice,
    :net_value,
    :vat_value,
    :gross_value,
    :amount,
    reference_invoice:
      {%{},
       [
         :amount,
         :net_value,
         :vat_value,
         :gross_value,
         :buyer_id_type,
         sales_invoice_items: [:net_value, :vat_value, :gross_value]
       ]},
    sales_invoice_items: [:net_value, :vat_value, :gross_value]
  ]

  @enforce_keys [:kind, :arguments, :confirmation_id, :context]
  defstruct [
    :kind,
    :arguments,
    :confirmation_id,
    :context,
    invoice: nil,
    currency_rate: nil,
    issued_id: nil,
    phase: :review,
    connection: nil,
    invoice_number: "",
    invoice_warnings: [],
    next_numbers_by_series: %{},
    errors: [],
    submission_info: nil,
    show_vat: true,
    # The invoice note and comment typed during review, kept apart from the loaded invoice so a
    # reload, also after one that failed, shows them again.
    edited_notes: nil
  ]

  @type kind :: :invoice | :correction
  @type t :: %__MODULE__{}

  @doc """
  Starts a confirmation for the arguments of a `preview_sales_invoice` (`:invoice`) or
  `preview_sales_invoice_correction` (`:correction`) call. `context` is the action context
  both the preview and the issuance run with.
  """
  @spec new(kind(), map(), String.t() | nil, map()) :: t()
  def new(kind, arguments, confirmation_id, context) when kind in [:invoice, :correction] do
    %__MODULE__{
      kind: kind,
      arguments: arguments,
      confirmation_id: confirmation_id,
      context: context
    }
  end

  @doc "Loads the review, or the issued document when this confirmation was already used."
  @spec load(t(), Scope.t()) :: t()
  def load(issuance, scope) do
    with {:ok, connection} <- Ksef.connection_status(scope: scope),
         {:ok, organization} <- Core.get_organization(scope.tenant, scope: scope),
         {:ok, existing} <- existing_confirmation(issuance, scope) do
      issuance = %{
        issuance
        | connection: connection,
          show_vat: organization.is_vat_payer,
          errors: []
      }

      case existing do
        nil -> load_preview(issuance, scope)
        :withdrawn -> withdrawn(issuance)
        invoice -> display_issued(issuance, invoice)
      end
    else
      {:error, _reason} ->
        %{
          issuance
          | invoice: nil,
            currency_rate: nil,
            errors: [gettext("Unable to load the invoice preview. Try again.")]
        }
    end
  end

  @doc "Selects the number typed or picked during review."
  @spec select_number(t(), String.t(), Scope.t()) :: t()
  def select_number(%{phase: :review, invoice: invoice} = issuance, number, scope) when not is_nil(invoice) do
    number = String.trim(number)

    %{
      issuance
      | invoice_number: number,
        invoice_warnings: number_warnings(issuance, number, scope),
        invoice: %{invoice | invoice_number: number},
        errors: []
    }
  end

  def select_number(issuance, _number, _scope), do: issuance

  @doc "Keeps the note printed on the invoice and the internal comment edited during review."
  @spec update_notes(t(), String.t(), String.t()) :: t()
  def update_notes(%{phase: :review, invoice: invoice} = issuance, note, comment) when not is_nil(invoice) do
    %{
      issuance
      | invoice: %{invoice | invoice_note: note, internal_note: comment},
        edited_notes: %{invoice_note: note, internal_note: comment}
    }
  end

  def update_notes(issuance, _note, _comment), do: issuance

  @doc "Issues the reviewed document when its data still matches the preview the user saw."
  @spec confirm(t(), Scope.t()) :: t()
  def confirm(%{phase: :review, invoice: invoice} = issuance, scope) when not is_nil(invoice) do
    with {:ok, %{status: :connected} = connection} <- Ksef.connection_status(scope: scope),
         {:ok, _result, current} <- preview(issuance, scope) do
      issuance = %{issuance | connection: connection}
      # The number and notes are edited in the widget, independently of the saved draft.
      current =
        Map.merge(current, Map.take(invoice, [:invoice_number, :invoice_note, :internal_note]))

      if Preview.review_snapshot(current) == Preview.review_snapshot(invoice) do
        issue(issuance, scope)
      else
        issuance
        |> load_preview(scope)
        |> Map.put(:errors, [
          gettext("The invoice data changed. Review the updated preview and confirm again.")
        ])
      end
    else
      {:ok, connection} ->
        %{
          issuance
          | connection: connection,
            errors: [gettext("Connect KSeF before issuing the invoice.")]
        }

      {:error, error} ->
        %{issuance | errors: error_messages(error)}
    end
  end

  def confirm(issuance, _scope), do: issuance

  @doc "Reloads the review, or the KSeF status of the issued document."
  @spec refresh(t(), Scope.t()) :: t()
  def refresh(%{issued_id: nil} = issuance, scope), do: load(issuance, scope)
  def refresh(issuance, scope), do: refresh_issued(issuance, scope)

  @doc "Applies a `{:ksef_invoice_status, _}` broadcast about the issued document."
  @spec ksef_status(t(), map(), Scope.t()) :: t()
  def ksef_status(%{issued_id: id} = issuance, %{invoice_id: id, status: status}, scope) when not is_nil(id) do
    # The submission worker has already withdrawn a document KSeF did not accept.
    if status == :failed, do: withdrawn(issuance), else: refresh_issued(issuance, scope)
  end

  def ksef_status(issuance, _status, _scope), do: issuance

  @doc "Drops loaded document data when the interface's authorization ends."
  @spec clear(t()) :: t()
  def clear(issuance),
    do: %{issuance | invoice: nil, currency_rate: nil, connection: nil, errors: [], submission_info: nil}

  @doc "Whether the user can confirm now: under review, connected to KSeF and numbered."
  @spec confirmable?(t()) :: boolean()
  def confirmable?(issuance) do
    issuance.phase == :review and not is_nil(issuance.invoice) and not is_nil(issuance.connection) and
      issuance.connection.status == :connected and issuance.invoice_number != ""
  end

  @doc "Names the document's state in the widget heading."
  @spec heading(t()) :: String.t()
  def heading(%{phase: :review, kind: :correction}), do: gettext("Confirm invoice correction")
  def heading(%{phase: :review}), do: gettext("Confirm invoice")
  def heading(%{phase: :submitting}), do: gettext("The invoice is being sent")
  def heading(%{phase: :submitted}), do: gettext("Invoice sent to KSeF")
  def heading(_issuance), do: gettext("KSeF submission failed")

  @doc "Explains the submission state after confirmation."
  @spec status_message(atom()) :: String.t()
  def status_message(:submitting), do: gettext("The invoice is saved. Sending to KSeF…")
  def status_message(:submitted), do: gettext("KSeF accepted the invoice.")
  def status_message(:failed), do: gettext("The invoice is saved, but KSeF submission failed.")

  def status_message(:not_submitted), do: gettext("The invoice is saved, but KSeF submission has not started.")

  def status_message(:returned_to_draft),
    do:
      gettext(
        "KSeF did not accept the invoice, so it returned to a draft without a number. Correct its details and issue it again."
      )

  def status_message(:deleted),
    do: gettext("The correction could not be sent and was removed. Prepare a new correction after fixing its details.")

  defp existing_confirmation(issuance, scope) do
    id = action_arguments(issuance)["invoice_id"] || issuance.confirmation_id

    case Invoicing.get_sales_invoice(id,
           scope: scope,
           load: @invoice_loads,
           not_found_error?: false
         ) do
      {:ok, %{invoice_number: number} = invoice} when not is_nil(number) -> {:ok, invoice}
      {:ok, _draft_or_missing} -> previous_attempt(issuance)
      {:error, reason} -> {:error, reason}
    end
  end

  defp previous_attempt(issuance) do
    # A withdrawn document keeps its terminal submission job. Reopening the same
    # confirmation must not issue it a second time.
    info = Ksef.get_submission_info(%{id: issuance.confirmation_id})
    {:ok, if(SubmissionInfo.attempted?(info), do: :withdrawn)}
  end

  defp load_preview(issuance, scope) do
    with {:ok, _result, invoice} <- preview(issuance, scope),
         {:ok, next_number} <-
           SalesInvoice.get_next_number(
             invoice.issue_date,
             series(issuance),
             action_arguments(issuance)["invoice_id"],
             scope: scope
           ) do
      number = invoice.invoice_number || next_number

      select_number(
        %{
          issuance
          | invoice: Map.merge(invoice, issuance.edited_notes || %{}),
            currency_rate: Invoicing.get_currency_rate(invoice),
            invoice_number: number,
            next_numbers_by_series:
              Invoicing.get_next_numbers_for_series(invoice.issue_date, [scope: scope],
                omit_invoice_id: action_arguments(issuance)["invoice_id"]
              ),
            phase: :review,
            errors: []
        },
        number,
        scope
      )
    else
      {:error, error} ->
        %{issuance | invoice: nil, currency_rate: nil, errors: error_messages(error)}
    end
  end

  # Runs the same authorized AshAi preview tool the model called, so the document matches the
  # one the model prepared, including the tool's loads.
  defp preview(issuance, %{actor: actor, tenant: tenant}) do
    name =
      if issuance.kind == :correction,
        do: :preview_sales_invoice_correction,
        else: :preview_sales_invoice

    [otp_app: :firmowid, tools: [name], actor: actor, tenant: tenant]
    |> AshAi.exposed_tools()
    |> Enum.find(&(&1.name == name))
    |> case do
      nil ->
        {:error, :forbidden}

      tool ->
        AshAi.Tools.execute(
          tool,
          issuance.arguments,
          %{actor: actor, tenant: tenant, context: issuance.context},
          encode?: false
        )
    end
  end

  defp series(%{kind: :correction}), do: "FK"
  defp series(_issuance), do: nil

  defp number_warnings(_issuance, "", _scope), do: []

  defp number_warnings(issuance, number, scope) do
    SalesInvoice.validate_number!(
      number,
      issuance.invoice.issue_date,
      action_arguments(issuance)["invoice_id"],
      scope: scope
    )
  end

  defp issue(issuance, scope) do
    case issue_document(issuance, scope) do
      {:ok, invoice} -> refresh_issued(%{issuance | issued_id: invoice.id}, scope)
      {:error, error} -> recover_confirmation(issuance, error, scope)
    end
  end

  defp issue_document(%{kind: :invoice} = issuance, scope) do
    case action_arguments(issuance)["invoice_id"] do
      nil ->
        Invoicing.issue_sales_invoice(
          %{input: confirmed_input(issuance), confirmation_id: issuance.confirmation_id},
          scope: scope,
          context: issuance.context
        )

      draft_id ->
        with {:ok, draft} <- Invoicing.get_sales_invoice(draft_id, scope: scope) do
          Invoicing.finalize_sales_invoice_draft(draft, %{input: confirmed_input(issuance)},
            scope: scope,
            private_arguments: %{expected_review: Preview.review_snapshot(issuance.invoice)},
            context: issuance.context
          )
        end
    end
  end

  defp issue_document(%{kind: :correction} = issuance, scope) do
    Invoicing.correct_sales_invoice(
      %{
        input: confirmed_input(issuance),
        original_invoice_id: action_arguments(issuance)["original_invoice_id"],
        confirmation_id: issuance.confirmation_id
      },
      scope: scope,
      context: issuance.context
    )
  end

  defp confirmed_input(issuance) do
    attrs = action_arguments(issuance)["invoice"] || %{}

    attrs
    |> Map.put("invoice_number", issuance.invoice_number)
    |> Map.put("issue_date", Date.to_iso8601(issuance.invoice.issue_date))
    |> Map.put("invoice_note", issuance.invoice.invoice_note)
    |> Map.put("internal_note", issuance.invoice.internal_note)
  end

  defp recover_confirmation(issuance, error, scope) do
    case existing_confirmation(issuance, scope) do
      {:ok, %{invoice_number: number} = invoice} when not is_nil(number) ->
        display_issued(issuance, invoice)

      {:ok, :withdrawn} ->
        withdrawn(issuance)

      _ ->
        operation = if issuance.kind == :correction, do: :correct, else: :issue
        FailureReporter.report_unexpected(error, operation, scope.tenant)
        %{issuance | errors: error_messages(error)}
    end
  end

  defp action_arguments(issuance), do: issuance.arguments["input"] || %{}

  defp refresh_issued(issuance, scope) do
    case Invoicing.get_sales_invoice(issuance.issued_id,
           scope: scope,
           load: @invoice_loads,
           not_found_error?: false
         ) do
      {:ok, %{invoice_number: number} = invoice} when not is_nil(number) ->
        display_issued(issuance, invoice)

      {:ok, _draft_or_missing} ->
        withdrawn(issuance)

      {:error, _reason} ->
        %{issuance | errors: [gettext("Unable to refresh the invoice status. Try again.")]}
    end
  end

  defp display_issued(issuance, invoice) do
    info = Ksef.get_submission_info(invoice)

    %{
      issuance
      | invoice: invoice,
        currency_rate: Invoicing.get_currency_rate(invoice),
        issued_id: invoice.id,
        phase: info.status,
        submission_info: info,
        errors: []
    }
  end

  # KSeF rejection removes a correction and returns an invoice to an unnumbered draft.
  defp withdrawn(issuance) do
    phase = if issuance.kind == :correction, do: :deleted, else: :returned_to_draft
    %{issuance | invoice: nil, currency_rate: nil, phase: phase, errors: []}
  end

  defp error_messages(%{errors: errors}) do
    errors
    |> Enum.flat_map(&form_errors/1)
    |> case do
      [] -> [gettext("Unable to issue the invoice. Check its details and try again.")]
      messages -> messages
    end
  end

  defp error_messages(error), do: error |> Ash.Error.to_error_class() |> error_messages()

  defp form_errors(error) do
    if Error.impl_for(error) do
      error
      |> Error.to_form_error()
      |> List.wrap()
      |> Enum.map(fn {_field, message, bindings} ->
        Inputs.translate_error({message, bindings})
      end)
    else
      []
    end
  end
end
