defmodule FirmowidWeb.Billing.Utilities.OcrLimit do
  @moduledoc """
  The plan's monthly limit of documents sent to OCR, for the screens: how many
  the organization used this month, and the refusal of one more.
  """

  alias Firmowid.Billing.PlanCatalog
  alias Firmowid.Blobs
  alias FirmowidUI.Components.Inputs

  @type usage :: %{used: non_neg_integer(), limit: PlanCatalog.limit()}

  @doc """
  Returns the documents the organization sent to OCR this month and the limit of
  its plan.
  """
  @spec usage(Firmowid.Scope.t(), map()) :: usage()
  def usage(scope, %{billing_plan: plan}) do
    %{
      used: Blobs.count_ocr_documents(scope: scope),
      limit: PlanCatalog.plan!(plan).monthly_ocr_documents
    }
  end

  @doc """
  Tells the user that a file was refused because the month's limit is used up,
  when `error` says so.
  """
  @spec toast_refusal(term(), String.t()) :: :ok
  def toast_refusal(error, filename) do
    with true <- Blobs.ocr_limit_error?(error),
         %{errors: errors} <- error,
         %{message: message} <- Enum.find(errors, &Blobs.ocr_limit_error?/1) do
      LiveToast.send_toast(:error, filename, title: Inputs.translate_error({message, []}))
    end

    :ok
  end
end
